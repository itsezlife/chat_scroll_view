/// Ticket 141: the panel's stickers flicker when a pack sheet opens and when
/// it closes.
///
/// **Seam:** a panel grid (`PanelCatalogViewport`) on the home route, and a
/// pack sheet (`PackSheet.show`, the touch route) whose own grid shows the
/// same pack, pushed and popped over it under the app's
/// `PlaybackOverlayPauseObserver`. The stickers are real
/// `LottieAnimationPaintable`s played by a real `LottieFrameScheduler` on a
/// `FrameTexturePool` of fake textures, on the scheduler's own clock frames.
/// Each frame the panel's layer is read: once every cell shows a texture, it
/// must go on showing that same texture through the open, while the sheet is
/// open, and through the close (no still, no other texture, no lease churn),
/// and no texture may be written with another asset's frame.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/overlay_pause_observer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

const _cells = 10;
const _info = LottieInfo(
  width: 512,
  height: 512,
  frameCount: 60,
  frameRate: 60,
  features: LottieFeatures.none,
);

ui.Image _image([int side = 4]) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

Future<ui.Image> _upload(Uint8List pixels, int side) => Future.value(_image());

/// Hands out a playing Lottie paintable for every request at once.
final class _LottieProducer implements AssetProducer {
  _LottieProducer(this.scheduler);

  final LottieFrameScheduler scheduler;
  var _handles = 0;

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    progress.advance(
      AssetStage.full,
      LottieAnimationPaintable(
        key: '${request.key}@${request.spec.pixelWidth}',
        handle: LottieHandle(++_handles),
        info: _info,
        firstFrame: _image(8),
        scheduler: scheduler,
        renderEdge: request.spec.pixelWidth,
      ),
      bytes: 64,
      tier: AssetTier.animated,
    );
    return _Task();
  }
}

final class _Task implements AssetTask {
  @override
  void cancel() {}
}

/// The texture ids composited in [layer]'s subtree, in paint order.
List<int> _textures(Layer? layer) {
  final ids = <int>[];
  void walk(Layer? layer) {
    if (layer == null) return;
    if (layer is TextureLayer) ids.add(layer.textureId);
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child);
      }
    }
  }

  walk(layer);
  return ids;
}

void main() {
  late PlaybackClock clock;
  late PlaybackActivity activity;
  late PlaybackOverlayPauseObserver observer;
  late FakeFrameTextureHost host;
  late FrameTexturePool pool;
  late FakeTextureFrameWriter writer;
  late LottieFrameScheduler scheduler;
  late AssetCacheScope scope;
  late FakeCatalogSnapshotSource panelSnapshots;
  late FakeCatalogSnapshotSource sheetSnapshots;
  late BuildContext home;
  late Widget Function() sheetGrid;
  var elapsed = Duration.zero;

  var lateWrites = false;

  List<CatalogSection> pack({String name = 'sticker', int count = _cells}) => [
    CatalogSection(
      id: name,
      title: name,
      leaves: [
        for (var i = 0; i < count; i++)
          CatalogLeaf.document(
            '$name-$i',
            semanticKind: SemanticKind.sticker,
            mediaForm: MediaForm.vectorAnimation,
            animated: true,
          ),
      ],
    ),
  ];

  Widget grid(FakeCatalogSnapshotSource snapshots, PanelCatalogController c) =>
      PanelCatalogTheme(
        data: PanelCatalogThemeData.light,
        child: PanelCatalogViewport(
          snapshots: snapshots,
          assets: scope,
          controller: c,
          spanCount: 5,
          cellExtent: 72,
          headerExtent: 24,
        ),
      );

  Future<void> pumpPanel(
    WidgetTester tester, {
    List<CatalogSection>? sheetPack,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    elapsed = Duration.zero;
    clock = PlaybackClock();
    activity = PlaybackActivity(clock: clock);
    observer = PlaybackOverlayPauseObserver(activity);
    host = FakeFrameTextureHost(buffersPerTexture: 4);
    pool = FrameTexturePool(host: host, now: () => elapsed);
    writer = FakeTextureFrameWriter();
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: FakeFrameRenderer(),
        memory: ListFramePageMemory(),
        upload: _upload,
      ),
      clock: clock,
      textures: pool,
      textureWriter: writer,
    );
    scope = AssetCacheScope(producer: _LottieProducer(scheduler), clock: clock);
    panelSnapshots = FakeCatalogSnapshotSource()..replaceSections(pack());
    sheetSnapshots = FakeCatalogSnapshotSource()
      ..replaceSections(sheetPack ?? pack());
    final panelController = PanelCatalogController();
    final sheetController = PanelCatalogController();
    addTearDown(() {
      observer.dispose();
      panelSnapshots.dispose();
      sheetSnapshots.dispose();
      panelController.dispose();
      sheetController.dispose();
      scope.dispose();
      scheduler.dispose();
      pool.dispose();
      activity.dispose();
      clock.dispose();
    });
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: Navigator(
          observers: [observer],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (context, _, _) => Builder(
              builder: (context) {
                home = context;
                return Column(
                  children: [
                    const Expanded(child: SizedBox.expand()),
                    SizedBox(
                      key: const Key('panel'),
                      height: 300,
                      child: grid(panelSnapshots, panelController),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    // The sheet's grid, built when the sheet opens.
    sheetGrid = () => grid(sheetSnapshots, sheetController);
  }

  /// One display frame of 16 ms; the elapsed time follows it.
  Future<void> frame(WidgetTester tester) async {
    elapsed += const Duration(milliseconds: 16);
    // A write lands a frame after it was sent.
    if (lateWrites) {
      writer
        ..resume()
        ..pause();
    }
    await tester.pump(const Duration(milliseconds: 16));
  }

  List<int> panelTextures(WidgetTester tester) => _textures(
    tester
        .renderObjectList<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
        .first
        .debugLayer,
  );

  for (final (name, other, late) in [
    ('of its pack', false, false),
    ('of its pack, writes a frame late', false, true),
    ('of another pack', true, false),
    ('of another pack, writes a frame late', true, true),
  ]) {
    testWidgets('the panel under a pack sheet $name keeps its textures '
        'through the open and the close', (tester) async {
      lateWrites = late;
      await pumpPanel(
        tester,
        sheetPack: other ? pack(name: 'other', count: 25) : null,
      );
      // Settle: every cell plays from a texture of its own.
      for (var i = 0; i < 120; i++) {
        await frame(tester);
      }
      final steady = panelTextures(tester);
      expect(steady, hasLength(_cells), reason: 'every cell on a texture');
      expect(steady.toSet(), hasLength(_cells));

      final changes = <String>[];
      void check(String phase, int i) {
        final now = panelTextures(tester);
        if (!listEquals(now, steady)) changes.add('$phase frame $i: $now');
      }

      PackSheet.show(
        home,
        arrangement: PanelArrangement.touch,
        builder: (_) => SizedBox(height: 400, child: sheetGrid()),
      ).ignore();
      for (var i = 0; i < 40; i++) {
        await frame(tester);
        check('open', i);
      }
      for (var i = 0; i < 60; i++) {
        await frame(tester);
        check('opened', i);
      }
      // The sheet's grid shows its stickers from textures: the panel's own
      // for the panel's pack (one entry, one lease), new ones for another.
      final sheet = _textures(
        tester
            .renderObjectList<RenderPanelCatalog>(
              find.byType(PanelCatalogViewport),
            )
            .last
            .debugLayer,
      );
      expect(sheet, hasLength(other ? 25 : _cells));
      expect(
        sheet.toSet().intersection(steady.toSet()),
        hasLength(other ? 0 : _cells),
      );
      Navigator.of(home).pop();
      for (var i = 0; i < 40; i++) {
        await frame(tester);
        check('close', i);
      }
      for (var i = 0; i < 60; i++) {
        await frame(tester);
        check('closed', i);
      }

      // No texture was written with another asset's frame.
      final sourceOf = <int, Object>{};
      final crossed = <String>[];
      for (final job in writer.batches.expand((batch) => batch)) {
        final first = sourceOf.putIfAbsent(job.texture.id, () => job.source);
        if (first != job.source)
          crossed.add('${job.texture.id}: ${job.source}');
      }
      await tester.pumpWidget(const SizedBox());
      scope.dispose();
      scheduler.dispose();
      clock.dispose();
      await tester.pump(const Duration(seconds: 3));
      expect(
        changes,
        isEmpty,
        reason: 'the panel showed: \n${changes.join('\n')}',
      );
      expect(crossed, isEmpty);
    });
  }
}
