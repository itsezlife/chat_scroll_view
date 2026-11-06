/// Ticket 55, symptom 1, thumbnail case (not fixed by ticket 56, which closed
/// the page-upload and stale-frame causes): "a weird flash when one [sticker or GIF cell] gets
/// loaded", especially while the panel scrolls.
///
/// **Run** (red on purpose; not part of `test/unit_test.dart`):
/// `cd example && flutter test test_diagnostic/flicker/thumbnail_fade_diagnosis_test.dart`
///
/// **Seam:** the real `PanelCatalogViewport` over a real `AssetCacheScope`
/// whose producer hands out what `VideoDecoder` hands out (a thumbnail still,
/// a first-frame still, then a `VideoAnimationPaintable`), played by the real
/// `VideoFrameScheduler` and frame pool of `test/support/flicker/video_rig.dart`. Page
/// uploads finish after a latency the test sets. Every pass the viewport paints
/// into a `SignatureCanvas`; a cell's passes form a timeline that must go
/// placeholder, still, animating without ever being less drawn than before
/// (`CellTimeline.flashes`).
///
/// Finding: when the first frame arrives over a thumbnail, the painter fades the
/// content in over the style's stand-in, not over the thumbnail, so the
/// thumbnail vanishes and the cell rebuilds from alpha 0.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:video_decoder/video_decoder.dart';

import '../../test/support/flicker/paint_signature.dart';
import '../../test/support/flicker/video_rig.dart';

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
        // ignore: invalid_use_of_visible_for_testing_member
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
    print('[thumbnail] $title\n  ${flashes.join('\n  ')}');
  }

  group('thumbnail to content', () {
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
  });
}
