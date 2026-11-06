/// Ticket 55, symptom 1: "a weird flash when one [sticker or GIF cell] gets
/// loaded", especially while the panel scrolls.
///
/// **Seam:** the real `PanelCatalogViewport` over a real `AssetCacheScope`
/// whose producer hands out what `VideoDecoder` hands out (a thumbnail still,
/// a first-frame still, then a `VideoAnimationPaintable`), played by the real
/// `VideoFrameScheduler` and frame pool of `support/video_rig.dart`. Page
/// uploads finish after a latency the test sets. Every pass the viewport paints
/// into a `SignatureCanvas`; a cell's passes form a timeline that must go
/// placeholder, still, animating without ever being less drawn than before
/// (`CellTimeline.flashes`).
///
/// **Run** (red on purpose; not part of `test/unit_test.dart`):
/// `cd example && flutter test test_diagnostic/flicker/panel_flash_diagnosis_test.dart`
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:video_decoder/video_decoder.dart';

import 'support/paint_signature.dart';
import 'support/video_rig.dart';

// 4 columns of 80 x 40 cells under a 24 px header, as in the viewport's own
// animated-sprite test.
Rect _cell(int i) =>
    Rect.fromLTWH((i % 4) * 80.0, 24.0 + (i ~/ 4) * 40, 80, 40);

/// Hands out what the decoder does, when the test says.
final class _GifProducer implements AssetProducer {
  _GifProducer(this.rig, {required this.thumbnails});

  final VideoRig rig;
  final bool thumbnails;
  final Map<int, AssetProgress> _waiting = {};

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final index = int.parse(
      RegExp(r'(\d+)').allMatches('${request.key}').last[1]!,
    );
    _waiting[index] = progress;
    if (thumbnails) {
      progress.advance(
        AssetStage.placeholder,
        VideoStillPaintable(VideoRig.solid()),
        bytes: 64,
      );
    }
    return _Task();
  }

  /// The clip of leaf [index] finishes decoding: first frame, then the
  /// animation, as `VideoDecoder._content` advances them.
  Future<void> finish(int index) async {
    final progress = _waiting.remove(index)!;
    final paintable = await rig.clip(index + 1);
    progress
      ..advance(
        AssetStage.firstFrame,
        VideoStillPaintable(VideoRig.solid()),
        bytes: 64,
      )
      ..advance(
        AssetStage.full,
        paintable,
        bytes: 64,
        tier: AssetTier.animated,
      );
  }
}

final class _Task implements AssetTask {
  @override
  void cancel() {}
}

void main() {
  late VideoRig rig;
  late _GifProducer producer;
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late AssetCacheScope scope;
  late List<CellTimeline> timelines;

  Future<void> pumpPanel(
    WidgetTester tester, {
    required int latency,
    required bool thumbnails,
    int cells = 8,
    int filler = 0,
  }) async {
    rig = VideoRig(latencySteps: latency);
    producer = _GifProducer(rig, thumbnails: thumbnails);
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    scope = AssetCacheScope(producer: producer, clock: rig.clock);
    timelines = [for (var i = 0; i < cells; i++) CellTimeline('cell $i')];
    snapshots.replaceSections([
      CatalogSection(
        id: 'gifs',
        title: 'GIFs',
        leaves: [
          for (var i = 0; i < cells + filler; i++)
            CatalogLeaf.document(
              'gif-$i',
              semanticKind: SemanticKind.gif,
              mediaForm: MediaForm.video,
              animated: true,
            ),
        ],
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: PanelCatalogThemeData.light,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 640,
                child: PanelCatalogViewport(
                  snapshots: snapshots,
                  assets: scope,
                  controller: controller,
                  spanCount: 4,
                  cellExtent: 40,
                  headerExtent: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    tester
        .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
        .debugFrameTime = () =>
        rig.now;
    addTearDown(() {
      snapshots.dispose();
      controller.dispose();
      scope.dispose();
      rig.dispose();
    });
  }

  /// One display frame; every cell's signature is recorded.
  Future<void> frame(WidgetTester tester, {bool paint = true}) => rig.step(
    flush: () async {
      if (paint) {
        final canvas = SignatureCanvas(rig.uploads.snapshots);
        tester
            .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
            .paint(TestRecordingPaintingContext(canvas), Offset.zero);
        for (var i = 0; i < timelines.length; i++) {
          timelines[i].passes.add(canvas.read(_cell(i)));
        }
      }
      await tester.pump(const Duration(milliseconds: 16));
    },
  );

  Future<void> frames(WidgetTester tester, int n, {bool paint = true}) async {
    for (var i = 0; i < n; i++) {
      await frame(tester, paint: paint);
    }
  }

  void report(String title, List<String> flashes) {
    // ignore: avoid_print
    print('[DEBUG-fl01-test] $title\n  ${flashes.join('\n  ')}');
  }

  group('symptom 1: a flash when a cell gets loaded', () {
    for (final latency in [0, 1, 3]) {
      testWidgets('a clip joins a page that is already on screen (upload takes '
          '$latency frames): never less drawn than before', (tester) async {
        await pumpPanel(tester, latency: latency, thumbnails: false);
        // Four GIFs load and play: they fill one page (2 x 2 cells).
        await frames(tester, 3);
        for (var i = 0; i < 4; i++) {
          await producer.finish(i);
        }
        await frames(tester, 40);
        // A fifth loads onto a second page, the sixth onto that same page,
        // which by then has an image.
        await producer.finish(4);
        await frames(tester, 40);
        timelines[5].passes.clear();
        await producer.finish(5);
        await frames(tester, 40);

        final flashes = [
          for (var i = 0; i < timelines.length; i++)
            ...timelines[i].flashes(ownTag: i + 1),
        ];
        report('latency $latency; cell 5: ${timelines[5].compact}', flashes);
        expect(flashes, isEmpty, reason: 'a drawn cell lost its content');
      });
    }

    testWidgets(
      'minimal: two clips on one page, the second joins (upload 1 frame)',
      (tester) async {
        await pumpPanel(tester, latency: 1, thumbnails: false, cells: 2);
        await frames(tester, 3);
        await producer.finish(0);
        await frames(tester, 20);
        await producer.finish(1);
        await frames(tester, 20);

        final flashes = timelines[1].flashes(ownTag: 2);
        report('minimal; cell 1: ${timelines[1].compact}', flashes);
        expect(flashes, isEmpty);
      },
    );

    testWidgets('a thumbnail is replaced by the loaded content without a dip', (
      tester,
    ) async {
      await pumpPanel(tester, latency: 0, thumbnails: true, cells: 1);
      await frames(tester, 5);
      await producer.finish(0);
      await frames(tester, 30);

      final flashes = timelines[0].flashes(ownTag: 1);
      report('thumbnail; cell 0: ${timelines[0].compact}', flashes);
      expect(flashes, isEmpty);
    });

    testWidgets(
      'control: one clip alone on its page, no thumbnail, never dips',
      (tester) async {
        await pumpPanel(tester, latency: 3, thumbnails: false, cells: 1);
        await frames(tester, 3);
        await producer.finish(0);
        await frames(tester, 30);

        final flashes = timelines[0].flashes(ownTag: 1);
        report('control; cell 0: ${timelines[0].compact}', flashes);
        expect(flashes, isEmpty);
      },
    );
  });

  group('symptom 1 variant: a lease that comes back shows a stale frame', () {
    testWidgets(
      'after the cell goes unpainted for over the sweep period, its first '
      'sprite is frame 0 of the new pass, not the frame it stopped on',
      (tester) async {
        await pumpPanel(
          tester,
          latency: 1,
          thumbnails: false,
          cells: 1,
          filler: 160,
        );
        await frames(tester, 3);
        await producer.finish(0);
        await frames(tester, 40);
        final before = timelines[0].passes.last.probe!.frame;
        timelines[0].passes.clear();

        // The panel is scrolled away for 1.5 s: the cell leaves the window,
        // its lease is not wanted, the sweep frees it. Then back.
        controller.jumpTo(3000);
        await frames(tester, 94, paint: false);
        controller.jumpTo(0);
        await frames(tester, 12);

        final firstFrames = [
          for (final s in timelines[0].passes)
            if (s.kind == CellKind.sprite && (s.probe?.alpha ?? 0) > 0)
              s.probe!.frame,
        ];
        report(
          'stopped on frame $before; frames shown after: '
          '${firstFrames.take(8).toList()}; ${timelines[0].compact}',
          const [],
        );
        expect(
          firstFrames.take(1),
          [0],
          reason: 'the restarted clip should start on its first frame',
        );
      },
    );
  });
}
