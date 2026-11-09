/// Ticket 141: a panel sticker jumps back to its start while the panel
/// scrolls, and on a drag past its top or bottom edge.
///
/// **Seam:** the real `PanelCatalogViewport` over a real `AssetCacheScope`
/// whose stickers are real `LottieAnimationPaintable`s, played by a real
/// `LottieFrameScheduler` on a `FrameTexturePool` of fake textures, on the
/// clock's own scheduler frames. The pointer drives the viewport. Each frame
/// the panel's layer is read: a cell that stays on screen must go on showing
/// its texture (its first-frame still drawn instead is the jump to the
/// start), and the frames written for it must never go back.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
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

// Long enough that no loop wraps within a test: a frame written lower than
// one before is a jump back.
const _info = LottieInfo(
  width: 512,
  height: 512,
  frameCount: 6000,
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
  final Map<ContentKey, LottieAnimationPaintable> made = {};
  var _handles = 0;

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final paintable = made[request.key] = LottieAnimationPaintable(
      key: '${request.key}@${request.spec.pixelWidth}',
      handle: LottieHandle(++_handles),
      info: _info,
      firstFrame: _image(8),
      scheduler: scheduler,
      renderEdge: request.spec.pixelWidth,
    );
    progress.advance(
      AssetStage.full,
      paintable,
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
  late FrameTexturePool pool;
  late FakeTextureFrameWriter writer;
  late LottieFrameScheduler scheduler;
  late _LottieProducer producer;
  late AssetCacheScope scope;
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  var elapsed = Duration.zero;

  Future<void> pumpPanel(WidgetTester tester, {int cells = 40}) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    elapsed = Duration.zero;
    clock = PlaybackClock();
    pool = FrameTexturePool(
      host: FakeFrameTextureHost(buffersPerTexture: 4),
      now: () => elapsed,
    );
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
    producer = _LottieProducer(scheduler);
    scope = AssetCacheScope(producer: producer, clock: clock);
    snapshots = FakeCatalogSnapshotSource()
      ..replaceSections([
        CatalogSection(
          id: 'pack',
          title: 'Pack',
          leaves: [
            for (var i = 0; i < cells; i++)
              CatalogLeaf.document(
                'sticker-$i',
                semanticKind: SemanticKind.sticker,
                mediaForm: MediaForm.vectorAnimation,
                animated: true,
              ),
          ],
        ),
      ]);
    controller = PanelCatalogController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 300,
            child: PanelCatalogTheme(
              data: PanelCatalogThemeData.light,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: scope,
                controller: controller,
                spanCount: 5,
                cellExtent: 72,
                headerExtent: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
    scheduler.dispose();
    pool.dispose();
    snapshots.dispose();
    controller.dispose();
    clock.dispose();
    await tester.pump(const Duration(seconds: 3));
  }

  RenderPanelCatalog panel(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  // The texture the first sticker's lease writes to, or null when it has
  // none on screen.
  int? textureOf(ContentKey key) => producer.made[key]?.texture?.id;

  /// A finger down on the middle of the panel, stamped with the test's time
  /// so the drag's velocity is measured.
  Future<TestGesture> press(WidgetTester tester) async {
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(find.byType(PanelCatalogViewport)),
      timeStamp: elapsed,
    );
    return gesture;
  }

  /// One display frame of 16 ms.
  Future<void> frame(WidgetTester tester) async {
    elapsed += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Plays until every cell on screen shows its texture.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 120; i++) {
      await frame(tester);
    }
  }

  /// Watches [key]'s cell through [run]: every frame its texture must be
  /// composited by the panel (not its still), and the frames written to
  /// it must not go back. Returns what went wrong, frame by frame.
  Future<List<String>> watch(
    WidgetTester tester,
    ContentKey key,
    Future<void> Function(Future<void> Function() frame) run,
  ) async {
    final faults = <String>[];
    var n = 0;
    var last = -1;
    var written = writer.batches.length;
    final texture = textureOf(key);
    expect(texture, isNotNull, reason: '$key settled on a texture');
    Future<void> step() async {
      await frame(tester);
      n++;
      final now = textureOf(key);
      final shown = _textures(panel(tester).debugLayer);
      if (now == null || !shown.contains(now)) {
        faults.add('frame $n: $key shows its still (texture $now)');
      } else if (now != texture) {
        faults.add('frame $n: $key moved to texture $now from $texture');
      }
      for (final job in writer.batches.skip(written).expand((b) => b)) {
        if (job.texture.id != texture) continue;
        if (job.frame < last) {
          faults.add(
            'frame $n: $key went back from frame $last to ${job.frame}',
          );
        }
        last = job.frame;
      }
      written = writer.batches.length;
    }

    final before = [
      for (final job in writer.batches.expand((b) => b))
        if (job.texture.id == texture) job.frame,
    ].last;
    await run(step);
    if (last <= before) {
      faults.add('$key did not play on: frame $last, $before before');
    }
    return faults;
  }

  const first = ContentKey.document('sticker-0');

  testWidgets('a cell on screen keeps playing through a slow drag', (
    tester,
  ) async {
    await pumpPanel(tester);
    await settle(tester);

    final faults = await watch(tester, first, (frame) async {
      final gesture = await press(tester);
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -1.5), timeStamp: elapsed);
        await frame();
      }
      for (var i = 0; i < 20; i++) {
        await frame();
      }
      await gesture.up(timeStamp: elapsed);
      for (var i = 0; i < 60; i++) {
        await frame();
      }
    });
    await dispose(tester);
    expect(faults, isEmpty);
  });

  testWidgets('a cell on screen keeps playing through a fling that keeps it '
      'there', (tester) async {
    await pumpPanel(tester);
    await settle(tester);

    // The fourth row: a short flick moves it up, never out.
    final faults = await watch(
      tester,
      const ContentKey.document('sticker-15'),
      (frame) async {
        final gesture = await press(tester);
        for (var i = 0; i < 3; i++) {
          await gesture.moveBy(const Offset(0, -20), timeStamp: elapsed);
          await frame();
        }
        await gesture.up(timeStamp: elapsed);
        for (var i = 0; i < 90; i++) {
          await frame();
        }
      },
    );
    await dispose(tester);
    expect(faults, isEmpty);
  });

  testWidgets('a cell keeps playing through a drag past the top edge', (
    tester,
  ) async {
    await pumpPanel(tester);
    await settle(tester);

    final faults = await watch(tester, first, (frame) async {
      final gesture = await press(tester);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 12), timeStamp: elapsed);
        await frame();
      }
      await gesture.up(timeStamp: elapsed);
      for (var i = 0; i < 90; i++) {
        await frame();
      }
    });
    await dispose(tester);
    expect(faults, isEmpty);
  });

  testWidgets('a cell keeps playing through a fling into the top edge', (
    tester,
  ) async {
    await pumpPanel(tester);
    await settle(tester);
    // Some way down first, the first row still in view.
    final down = await press(tester);
    for (var i = 0; i < 10; i++) {
      await down.moveBy(const Offset(0, -3), timeStamp: elapsed);
      await frame(tester);
    }
    for (var i = 0; i < 10; i++) {
      await frame(tester);
    }
    await down.up(timeStamp: elapsed);
    await settle(tester);

    final faults = await watch(tester, first, (frame) async {
      final gesture = await press(tester);
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 20), timeStamp: elapsed);
        await frame();
      }
      await gesture.up(timeStamp: elapsed);
      for (var i = 0; i < 90; i++) {
        await frame();
      }
    });
    await dispose(tester);
    expect(faults, isEmpty);
  });

  testWidgets('a cell keeps playing through a drag past the bottom edge', (
    tester,
  ) async {
    // Two rows: nothing to scroll, every drag is past an edge.
    await pumpPanel(tester, cells: 10);
    await settle(tester);

    final faults = await watch(tester, first, (frame) async {
      final gesture = await press(tester);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -12), timeStamp: elapsed);
        await frame();
      }
      await gesture.up(timeStamp: elapsed);
      for (var i = 0; i < 90; i++) {
        await frame();
      }
    });
    await dispose(tester);
    expect(faults, isEmpty);
  });
}
