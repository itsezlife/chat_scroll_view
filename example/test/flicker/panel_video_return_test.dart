/// Ticket 148: a video sticker cell scrolled off and back must go on from the
/// frame it showed when it left, at once: on the first frame back it shows
/// exactly that frame, and from there it moves one frame per frame interval
/// of the clip, with no hold of several frames and no skip ahead by the time
/// it was away.
///
/// **Seam:** the real `PanelCatalogViewport` over a real `AssetCacheScope`
/// whose stickers are real `VideoAnimationPaintable`s, played by a real
/// `VideoFrameScheduler` on a `FrameTexturePool` of fake textures, on the
/// clock's own scheduler frames. The engine stamps each frame's index into
/// its pixels and the writer reads it as it posts, so the test knows which
/// frame of the clip each texture holds, frame by frame.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

// 30 frames a second, long enough that no loop wraps within a test.
const _rate = 30;
const _frames = 6000;
const _info = VideoInfo(
  width: 512,
  height: 512,
  duration: Duration(milliseconds: _frames * 1000 ~/ _rate),
  frameRate: _rate * 1.0,
  hasAlpha: true,
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

/// The fake engine, with each frame's index written over its first pixel.
final class _StampingEngine implements VideoEngine {
  final FakeVideoEngine inner = FakeVideoEngine();

  @override
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) => inner.open(bytes, width: width, height: height);

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    final result = await inner.nextFrame(clip, destination: destination);
    if (result.status == VideoFrameStatus.frame) {
      final index = (result.ptsMs * _rate / 1000).round();
      destination.buffer
          .asByteData(destination.offsetInBytes)
          .setUint32(0, index);
    }
    return result;
  }

  @override
  Future<bool> rewind(VideoClip clip) => inner.rewind(clip);

  @override
  Future<void> close(VideoClip clip) => inner.close(clip);

  @override
  Future<void> dispose() => inner.dispose();
}

int _indexOf(Uint8List pixels) =>
    pixels.buffer.asByteData(pixels.offsetInBytes).getUint32(0);

/// Posts every frame, and keeps the clip frame each texture holds.
final class _ReadingWriter implements TextureFrameWriter {
  final FakeTextureFrameWriter inner = FakeTextureFrameWriter();

  /// The clip frame index each texture id holds now.
  final Map<int, int> holds = {};

  @override
  Future<List<TextureFrameOutcome>> write(List<TextureFrameJob> jobs) async {
    final indices = [
      for (final job in jobs)
        _indexOf((job.source as VideoFrameSource).pixelsOf(job.frame)!),
    ];
    final outcomes = await inner.write(jobs);
    for (var i = 0; i < jobs.length; i++) {
      if (outcomes[i] == TextureFrameOutcome.posted) {
        holds[jobs[i].texture.id] = indices[i];
      }
    }
    return outcomes;
  }
}

/// Hands out a playing video paintable for every request, once its clip
/// opens.
final class _VideoProducer implements AssetProducer {
  _VideoProducer(this.engine, this.scheduler);

  static final Uint8List bytes = Uint8List.fromList([1, 2, 3]);

  final _StampingEngine engine;
  final VideoFrameScheduler scheduler;
  final Map<ContentKey, VideoAnimationPaintable> made = {};

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final width = request.spec.pixelWidth;
    final height = request.spec.pixelHeight;
    engine.open(bytes, width: width, height: height).then((result) {
      final clip = (result as VideoClipOpened).clip;
      final paintable = made[request.key] = VideoAnimationPaintable(
        key: '${request.key}@$width',
        clip: clip,
        firstFrame: _image(8),
        scheduler: scheduler,
        onDispose: () => engine.close(clip),
      );
      progress.advance(
        AssetStage.full,
        paintable,
        bytes: 64,
        tier: AssetTier.animated,
      );
    }).ignore();
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
  late _ReadingWriter writer;
  late _StampingEngine engine;
  late VideoFrameScheduler scheduler;
  late _VideoProducer producer;
  late AssetCacheScope scope;
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  var elapsed = Duration.zero;

  Future<void> pumpPanel(WidgetTester tester, {int cells = 100}) async {
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
    writer = _ReadingWriter();
    engine = _StampingEngine()
      ..inner.accept(_VideoProducer.bytes, _info, frameCount: _frames);
    scheduler = VideoFrameScheduler(
      engine: engine,
      atlas: VideoFrameAtlas.create(upload: _upload),
      clock: clock,
      textures: pool,
      textureWriter: writer,
    );
    producer = _VideoProducer(engine, scheduler);
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
                mediaForm: MediaForm.video,
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
    await engine.dispose();
    await tester.pump(const Duration(seconds: 3));
  }

  RenderPanelCatalog panel(WidgetTester tester) => tester
      .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport));

  /// One display frame of 16 ms.
  Future<void> frame(WidgetTester tester) async {
    elapsed += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 16));
  }

  const first = ContentKey.document('sticker-0');

  /// The clip frame [key]'s cell shows on screen now, or null when the panel
  /// composites no texture of it (its still, or nothing).
  int? shownFrame(WidgetTester tester, ContentKey key) {
    final texture = producer.made[key]?.texture?.id;
    if (texture == null) return null;
    if (!_textures(panel(tester).debugLayer).contains(texture)) return null;
    return writer.holds[texture];
  }

  for (final away in [18, 40]) {
    testWidgets('a video cell scrolled off for ${away * 16} ms and back shows '
        'the frame it left on, then one frame per frame interval', (
      tester,
    ) async {
      await pumpPanel(tester);
      for (var i = 0; i < 120; i++) {
        await frame(tester);
      }
      final left = shownFrame(tester, first);
      expect(left, isNotNull, reason: 'it plays on a texture');

      controller.jumpTo(180);
      await frame(tester);
      await frame(tester);
      expect(
        producer.made[first]!.texture,
        isNull,
        reason: 'it left: its lease went',
      );
      for (var i = 0; i < away; i++) {
        await frame(tester);
      }

      controller.jumpTo(0);
      await frame(tester);
      final shown = [shownFrame(tester, first)];
      // A second of display frames: 30 frames of the clip.
      for (var i = 0; i < 60; i++) {
        await frame(tester);
        shown.add(shownFrame(tester, first));
      }
      await dispose(tester);

      expect(
        shown.first,
        left,
        reason: 'the first frame back is the one it left on; shown: $shown',
      );
      // Display frame k after the return shows clip frame left + k * 16 ms
      // at 30 frames a second, give or take one frame of the clip.
      for (var k = 0; k < shown.length; k++) {
        final due = left! + k * 16 * _rate ~/ 1000;
        expect(
          shown[k],
          inInclusiveRange(due - 1, due + 1),
          reason: 'display frame $k back shows frame $due; shown: $shown',
        );
      }
    });
  }
}
