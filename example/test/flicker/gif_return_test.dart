/// Ticket 150: a GIF scrolled off and back goes on from the frame it left on,
/// one frame of the clip at a time at the clip's rate, with no hold and no
/// catch-up a few frames later, on a screen of GIFs the size a phone shows.
///
/// **Seam:** the real `PanelCatalogViewport` over a real `AssetCacheScope`
/// whose cells are real `VideoAnimationPaintable`s, played by a real
/// `VideoFrameScheduler` with its default budgets, on a `FrameTexturePool` of
/// fake textures and a real frame atlas, on the clock's own scheduler frames.
/// The engine stamps each frame's index and its clip into the pixels, and the
/// texture writer and the atlas renderer read them as they post or draw, so
/// the test knows which frame of the clip the cell shows, display frame by
/// display frame, on a texture or on a slot.
///
/// The geometry is a phone's: a 1080 x 2400 screen at 3x, a panel of three
/// GIFs a row, so a screen of cells leaves and comes back together, as on
/// the panel's GIF page or a chat of GIFs.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
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

// Long enough that no loop wraps within a test.
const _frames = 6000;

VideoInfo _infoAt(int rate) => VideoInfo(
  width: 360,
  height: 360,
  duration: Duration(milliseconds: _frames * 1000 ~/ rate),
  frameRate: rate * 1.0,
  hasAlpha: false,
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

// A decoded frame's first eight bytes: its index in the clip, then the clip.
int _indexOf(Uint8List pixels) =>
    pixels.buffer.asByteData(pixels.offsetInBytes).getUint32(0);
int _clipOf(Uint8List pixels) =>
    pixels.buffer.asByteData(pixels.offsetInBytes).getUint32(4);

/// The fake engine, with each frame's index and clip written over its first
/// pixels.
final class _StampingEngine implements VideoEngine {
  _StampingEngine(this.rate);

  final int rate;
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
      destination.buffer.asByteData(destination.offsetInBytes)
        ..setUint32(0, (result.ptsMs * rate / 1000).round())
        ..setUint32(4, clip.id);
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

/// Draws frames into the atlas's pages, and keeps the clip frame each clip's
/// slot holds.
final class _ReadingRenderer implements FrameRenderer {
  final FrameRenderer inner = const VideoFrameRenderer();

  /// The clip frame index each clip id's slot holds now.
  final Map<int, int> holds = {};

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    final pixels = [
      for (final job in jobs)
        (job.source as VideoFrameSource).pixelsOf(job.frame),
    ];
    final drawn = await inner.render(jobs, memory);
    for (final i in drawn) {
      if (pixels[i] case final frame?) holds[_clipOf(frame)] = _indexOf(frame);
    }
    return drawn;
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
  final Map<ContentKey, VideoClip> clips = {};

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final width = request.spec.pixelWidth;
    final height = request.spec.pixelHeight;
    engine.open(bytes, width: width, height: height).then((result) {
      final clip = clips[request.key] = (result as VideoClipOpened).clip;
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
  late _ReadingRenderer renderer;
  late _StampingEngine engine;
  late VideoFrameScheduler scheduler;
  late _VideoProducer producer;
  late AssetCacheScope scope;
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  var elapsed = Duration.zero;

  // A phone: 360 x 800 points at 3x; the panel is a keyboard's height, three
  // GIFs of 120 points a row, so a cell's clip is 360 px a side.
  const panelHeight = 330.0;
  const cellExtent = 120.0;

  Future<void> pumpPanel(WidgetTester tester, {required int rate}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    elapsed = Duration.zero;
    clock = PlaybackClock();
    pool = FrameTexturePool(
      host: FakeFrameTextureHost(buffersPerTexture: 4),
      now: () => elapsed,
    );
    writer = _ReadingWriter();
    renderer = _ReadingRenderer();
    engine = _StampingEngine(rate)
      ..inner.accept(_VideoProducer.bytes, _infoAt(rate), frameCount: _frames);
    scheduler = VideoFrameScheduler(
      engine: engine,
      atlas: FrameAtlas<Object>(
        renderer: renderer,
        memory: ListFramePageMemory(),
        sizeClasses: VideoFrameSize.defaultClasses,
        pageSideFor: VideoFrameAtlas.pageSideFor,
        upload: _upload,
        // As `VideoFrameAtlas.create` makes it.
        forgetIdleFrames: true,
      ),
      clock: clock,
      textures: pool,
      textureWriter: writer,
    );
    producer = _VideoProducer(engine, scheduler);
    scope = AssetCacheScope(producer: producer, clock: clock);
    snapshots = FakeCatalogSnapshotSource()
      ..replaceSections([
        CatalogSection(
          id: 'gifs',
          title: 'GIFs',
          leaves: [
            for (var i = 0; i < 90; i++)
              CatalogLeaf.document(
                'gif-$i',
                semanticKind: SemanticKind.gif,
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
            height: panelHeight,
            child: PanelCatalogTheme(
              data: PanelCatalogThemeData.light,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: scope,
                controller: controller,
                spanCount: 3,
                cellExtent: cellExtent,
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

  const first = ContentKey.document('gif-0');

  /// The clip frame [key]'s cell shows on screen now: the one its texture
  /// holds while the panel composites it, else the one its slot holds while
  /// it has a sprite; null when it shows its still, or nothing.
  int? shownFrame(WidgetTester tester, ContentKey key) {
    final paintable = producer.made[key];
    if (paintable == null) return null;
    if (paintable.texture?.id case final texture?) {
      if (!_textures(panel(tester).debugLayer).contains(texture)) return null;
      return writer.holds[texture];
    }
    if (paintable.sprite == null) return null;
    return renderer.holds[producer.clips[key]!.id];
  }

  /// [shown] goes on from frame [from] one frame of the clip at a time, at
  /// the clip's [rate]: every display frame shows a frame of the clip, never
  /// more than one ahead of the one before (no catch-up), and display frame k
  /// shows the frame due k display frames after [from], give or take one
  /// frame of the clip (where in its time [from] was is not known): no hold.
  void expectPlaysOn(List<int?> shown, {required int from, required int rate}) {
    expect(shown, everyElement(isNotNull), reason: 'shown: $shown');
    for (var k = 1; k < shown.length; k++) {
      expect(
        shown[k]! - shown[k - 1]!,
        inInclusiveRange(0, 1),
        reason:
            'display frame $k back moves on by one frame of the clip at '
            'most: no catch-up; shown: $shown',
      );
    }
    for (var k = 0; k < shown.length; k++) {
      final due = from + k * 16 * rate ~/ 1000;
      expect(
        shown[k],
        inInclusiveRange(due - 1, due + 1),
        reason: 'display frame $k back shows frame $due; shown: $shown',
      );
    }
  }

  Future<void> stay(WidgetTester tester, Duration time) async {
    for (
      var t = Duration.zero;
      t < time;
      t += const Duration(milliseconds: 16)
    ) {
      await frame(tester);
    }
  }

  /// Plays [first] for two seconds, runs [away] with it off screen, scrolls
  /// back to it and answers the frame it showed when it left and the frames
  /// it shows for a second and a quarter after it is back.
  Future<({int left, List<int?> shown})> leaveAndReturn(
    WidgetTester tester, {
    required int rate,
    required Future<void> Function() away,
  }) async {
    await pumpPanel(tester, rate: rate);
    await stay(tester, const Duration(seconds: 2));
    final left = shownFrame(tester, first);
    expect(left, isNotNull, reason: 'it plays');
    await away();
    expect(
      producer.made[first]!.texture,
      isNull,
      reason: 'it left: its lease went',
    );
    controller.jumpTo(0);
    await frame(tester);
    final shown = [shownFrame(tester, first)];
    for (var i = 0; i < 78; i++) {
      await frame(tester);
      shown.add(shownFrame(tester, first));
    }
    await dispose(tester);
    return (left: left!, shown: shown);
  }

  for (final rate in [10, 15, 25]) {
    for (final away in const [
      Duration(milliseconds: 300),
      Duration(seconds: 1),
    ]) {
      testWidgets('a $rate fps GIF scrolled off with its screen for '
          '${away.inMilliseconds} ms and back shows the frame it left on, '
          'then the next one at each frame of the clip', (tester) async {
        final (:left, :shown) = await leaveAndReturn(
          tester,
          rate: rate,
          away: () async {
            // Its screen leaves (the three rows from the top, 24 + 3 x 120
            // points), and as many cells come.
            controller.jumpTo(384);
            await stay(tester, away);
          },
        );
        expect(
          shown.first,
          left,
          reason: 'the first frame back is the one it left on; shown: $shown',
        );
        expectPlaysOn(shown, from: left, rate: rate);
      });
    }

    testWidgets('a $rate fps GIF that comes back after its kept frames went '
        'to the screens after it starts over from its first frame, then the '
        'next one at each frame of the clip', (tester) async {
      final (left: _, :shown) = await leaveAndReturn(
        tester,
        rate: rate,
        away: () async {
          // Four screens, a quarter of a second each: their cells take the
          // memory kept for the ones that left before them.
          for (var screen = 1; screen <= 4; screen++) {
            controller.jumpTo(384.0 * screen);
            await stay(tester, const Duration(milliseconds: 250));
          }
        },
      );
      // Its still is its first frame: until a frame of the clip shows, the
      // cell shows that.
      final firstShown = shown.indexWhere((frame) => frame != null);
      expect(firstShown, isNot(-1), reason: 'it plays again; shown: $shown');
      expectPlaysOn(
        [for (var k = 0; k < shown.length; k++) k < firstShown ? 0 : shown[k]],
        from: 0,
        rate: rate,
      );
    });
  }
}
