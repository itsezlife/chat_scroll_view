/// Ticket 151: after the app was paused (its window lost focus, or it was
/// hidden) and resumed, every sticker on screen must go on from the frame it
/// stopped on, at once: on the first frame back it shows that frame (or the
/// one the first tick back posts), and from there it moves one frame per
/// frame interval, with no hold of several frames and no burst to catch up.
///
/// **Seam:** the real `PanelCatalogViewport` over a real `AssetCacheScope`,
/// paused by a real `PlaybackActivity` that follows the widgets binding's
/// lifecycle (`WidgetsPlaybackLifecycleSource`), whose stickers are real
/// `LottieAnimationPaintable`s or `VideoAnimationPaintable`s, played by the
/// real schedulers on a `FrameTexturePool` of fake textures with Android's
/// buffer count, on the clock's own scheduler frames. The writer records
/// which frame of its animation each texture holds, so the test reads, frame
/// by frame, what every cell composites.
///
/// The panel is a phone's: more cells on screen than the pool keeps frames
/// for when they all let go of their textures at once.
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
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

// Long enough that no loop wraps within a test.
const _lottieRate = 60;
const _lottieInfo = LottieInfo(
  width: 512,
  height: 512,
  frameCount: 6000,
  frameRate: _lottieRate * 1.0,
  features: LottieFeatures.none,
);

const _videoRate = 30;
const _videoFrames = 6000;
const _videoInfo = VideoInfo(
  width: 512,
  height: 512,
  duration: Duration(milliseconds: _videoFrames * 1000 ~/ _videoRate),
  frameRate: _videoRate * 1.0,
  hasAlpha: true,
);

// Cells on screen: six rows of five, 30 textures of 1 MiB, more than the
// 24 MiB the pool keeps frames for.
const _rows = 6;
const _columns = 5;
const _cellExtent = 72.0;

ui.Image _image([int side = 4]) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

Future<ui.Image> _upload(Uint8List pixels, int side) => Future.value(_image());

final class _Task implements AssetTask {
  @override
  void cancel() {}
}

/// Hands out a playing Lottie paintable for every request at once.
final class _LottieProducer implements AssetProducer {
  _LottieProducer(this.scheduler);

  final LottieFrameScheduler scheduler;
  final Map<ContentKey, AssetPaintable> made = {};
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
      info: _lottieInfo,
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

/// The fake video engine, with each frame's index written over its first
/// pixel.
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
      final index = (result.ptsMs * _videoRate / 1000).round();
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

/// Hands out a playing video paintable for every request, once its clip
/// opens.
final class _VideoProducer implements AssetProducer {
  _VideoProducer(this.engine, this.scheduler);

  static final Uint8List bytes = Uint8List.fromList([1, 2, 3]);

  final _StampingEngine engine;
  final VideoFrameScheduler scheduler;
  final Map<ContentKey, AssetPaintable> made = {};

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

/// Posts every frame, and keeps the frame each texture holds.
final class _ReadingWriter implements TextureFrameWriter {
  final FakeTextureFrameWriter inner = FakeTextureFrameWriter();

  /// The animation frame each texture id holds now.
  final Map<int, int> holds = {};

  @override
  Future<List<TextureFrameOutcome>> write(List<TextureFrameJob> jobs) async {
    final indices = [for (final job in jobs) _frameOf(job)];
    final outcomes = await inner.write(jobs);
    for (var i = 0; i < jobs.length; i++) {
      if (outcomes[i] == TextureFrameOutcome.posted) {
        holds[jobs[i].texture.id] = indices[i];
      }
    }
    return outcomes;
  }

  // A Lottie job names its frame; a video job's frame is a buffer whose
  // pixels the engine stamped.
  static int _frameOf(TextureFrameJob job) => switch (job.source) {
    final VideoFrameSource source =>
      source
          .pixelsOf(job.frame)!
          .buffer
          .asByteData(source.pixelsOf(job.frame)!.offsetInBytes)
          .getUint32(0),
    _ => job.frame,
  };
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

enum _Kind { lottie, video }

/// One playing panel: what a test builds, reads and tears down.
final class _Rig {
  factory _Rig(_Kind kind, Duration Function() now) {
    final clock = PlaybackClock();
    final pool = FrameTexturePool(
      host: FakeFrameTextureHost(buffersPerTexture: 4),
      now: now,
    );
    final writer = _ReadingWriter();
    final AssetProducer producer;
    final Map<ContentKey, AssetPaintable> made;
    final List<Future<void> Function()> tearDown;
    switch (kind) {
      case _Kind.lottie:
        final scheduler = LottieFrameScheduler(
          atlas: FrameAtlas<Object>(
            renderer: FakeFrameRenderer(),
            memory: ListFramePageMemory(),
            upload: _upload,
          ),
          clock: clock,
          textures: pool,
          textureWriter: writer,
        );
        final lottie = _LottieProducer(scheduler);
        producer = lottie;
        made = lottie.made;
        tearDown = [() async => scheduler.dispose()];
      case _Kind.video:
        final engine = _StampingEngine()
          ..inner.accept(
            _VideoProducer.bytes,
            _videoInfo,
            frameCount: _videoFrames,
          );
        final scheduler = VideoFrameScheduler(
          engine: engine,
          atlas: VideoFrameAtlas.create(upload: _upload),
          clock: clock,
          textures: pool,
          textureWriter: writer,
          // Every clip on screen served every tick: the cap's time-slicing
          // is a cadence of its own, not what this test is about.
          maxAdvancing: _rows * _columns,
        );
        final video = _VideoProducer(engine, scheduler);
        producer = video;
        made = video.made;
        tearDown = [() async => scheduler.dispose(), engine.dispose];
    }
    final lifecycle = WidgetsPlaybackLifecycleSource();
    return _Rig._(
      kind: kind,
      clock: clock,
      pool: pool,
      writer: writer,
      made: made,
      scope: AssetCacheScope(producer: producer, clock: clock),
      lifecycle: lifecycle,
      activity: PlaybackActivity(clock: clock, lifecycle: lifecycle),
      tearDown: tearDown,
    );
  }

  _Rig._({
    required this.kind,
    required this.clock,
    required this.pool,
    required this.writer,
    required this.made,
    required this.scope,
    required this.lifecycle,
    required this.activity,
    required this.tearDown,
  });

  final _Kind kind;
  final PlaybackClock clock;
  final FrameTexturePool pool;
  final _ReadingWriter writer;
  final Map<ContentKey, AssetPaintable> made;
  final AssetCacheScope scope;
  final WidgetsPlaybackLifecycleSource lifecycle;
  final PlaybackActivity activity;
  final List<Future<void> Function()> tearDown;

  /// Animation frames a second.
  int get rate => kind == _Kind.lottie ? _lottieRate : _videoRate;

  /// The most frames of its own a cell moves in one 16 ms display frame:
  /// a Lottie cell at its 30 fps cap posts every other display frame, two
  /// frames of its 60; a 30 fps clip moves one, or two after a frame it
  /// dropped to the cadence.
  int get maxStep => 2;

  /// The most display frames of 16 ms a cell may show one frame for: two at
  /// a 30 fps cap, three for a 30 fps clip, whose 33 ms frames sometimes
  /// span three.
  int get maxHold => kind == _Kind.lottie ? 2 : 3;

  MediaForm get form =>
      kind == _Kind.lottie ? MediaForm.vectorAnimation : MediaForm.video;

  Future<void> dispose() async {
    activity.dispose();
    lifecycle.dispose();
    scope.dispose();
    for (final step in tearDown) {
      await step();
    }
    pool.dispose();
    clock.dispose();
  }
}

/// How the app goes away and comes back, as the platform reports it.
typedef _Trip = ({
  String name,
  List<AppLifecycleState> away,
  List<AppLifecycleState> back,
});

const List<_Trip> _trips = [
  // The window loses focus: a notification shade, a system dialog.
  (
    name: 'loses focus',
    away: [AppLifecycleState.inactive],
    back: [AppLifecycleState.resumed],
  ),
  // The app goes to the background and comes back.
  (
    name: 'is hidden',
    away: [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ],
    back: [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ],
  ),
];

void main() {
  var elapsed = Duration.zero;

  Future<_Rig> pumpPanel(WidgetTester tester, _Kind kind) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The binding's lifecycle is the process's: back to resumed after.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    elapsed = Duration.zero;
    final rig = _Rig(kind, () => elapsed);
    final snapshots = FakeCatalogSnapshotSource()
      ..replaceSections([
        CatalogSection(
          id: 'pack',
          title: 'Pack',
          leaves: [
            for (var i = 0; i < 100; i++)
              CatalogLeaf.document(
                'sticker-$i',
                semanticKind: SemanticKind.sticker,
                mediaForm: rig.form,
                animated: true,
              ),
          ],
        ),
      ]);
    final controller = PanelCatalogController();
    addTearDown(snapshots.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            // The section's header and its rows, no more.
            height: 24 + _rows * _cellExtent,
            child: PanelCatalogTheme(
              data: PanelCatalogThemeData.light,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: rig.scope,
                controller: controller,
                spanCount: _columns,
                cellExtent: _cellExtent,
                headerExtent: 24,
              ),
            ),
          ),
        ),
      ),
    );
    return rig;
  }

  Future<void> dispose(WidgetTester tester, _Rig rig) async {
    await tester.pumpWidget(const SizedBox());
    await rig.dispose();
    await tester.pump(const Duration(seconds: 3));
  }

  /// One display frame of 16 ms.
  Future<void> frame(WidgetTester tester) async {
    elapsed += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// The frame each cell on screen composites now; null for a cell that
  /// shows no texture (its still, or nothing).
  Map<ContentKey, int?> shown(WidgetTester tester, _Rig rig) {
    final composited = _textures(
      tester
          .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
          .debugLayer,
    );
    return {
      for (var i = 0; i < _rows * _columns; i++)
        ContentKey.document(
          'sticker-$i',
        ): switch (rig.made[ContentKey.document('sticker-$i')]?.texture?.id) {
          final id? when composited.contains(id) => rig.writer.holds[id],
          _ => null,
        },
    };
  }

  for (final kind in _Kind.values) {
    for (final trip in _trips) {
      testWidgets('${kind.name} stickers go on from their frames after the '
          'app ${trip.name} for 3 s', (tester) async {
        final rig = await pumpPanel(tester, kind);
        for (var i = 0; i < 120; i++) {
          await frame(tester);
        }
        trip.away.forEach(tester.binding.handleAppLifecycleStateChanged);
        expect(rig.clock.isPaused, isTrue, reason: 'playback paused');
        for (var i = 0; i < 3000 ~/ 16; i++) {
          await frame(tester);
        }
        // What each cell stopped on, once the frames in flight landed.
        final left = shown(tester, rig);
        expect(
          left.values,
          everyElement(isNotNull),
          reason: 'every cell shows its texture while paused: $left',
        );
        trip.back.forEach(tester.binding.handleAppLifecycleStateChanged);
        expect(rig.clock.isPaused, isFalse, reason: 'playback resumed');

        await frame(tester);
        final back = [shown(tester, rig)];
        // Half a second of display frames.
        for (var i = 0; i < 30; i++) {
          await frame(tester);
          back.add(shown(tester, rig));
        }
        await dispose(tester, rig);

        final faults = <String>[];
        for (final MapEntry(:key, value: from) in left.entries) {
          final frames = [for (final step in back) step[key]];
          // Its texture shows at once, holding the frame it stopped on;
          // the post of the first tick back may already have landed on it,
          // one step on.
          switch (frames.first) {
            case null:
              faults.add('$key: first frame back shows no texture');
              continue;
            case final first when first < from! || first - from > rig.maxStep:
              faults.add('$key: first frame back $first, left on $from');
              continue;
          }
          // From there it plays as it did: never back, never held past a
          // frame interval of its cap, never more than one frame of its
          // own per display frame, and as far along after half a second as
          // half a second of playback takes it.
          for (var k = 1; k < frames.length; k++) {
            final (at, previous) = (frames[k], frames[k - 1]!);
            if (at == null || at < previous || at - previous > rig.maxStep) {
              faults.add('$key: frame $k back shows $at after $previous');
              break;
            }
            if (k >= rig.maxHold &&
                frames.sublist(k - rig.maxHold, k + 1).toSet().length == 1) {
              faults.add('$key: held $at for ${rig.maxHold + 1} frames');
              break;
            }
          }
          final due = from + (frames.length - 1) * 16 * rig.rate ~/ 1000;
          if (frames.last case final last? when (last - due).abs() > 2) {
            faults.add(
              '$key: ${frames.length - 1} frames back shows $last, '
              'due $due',
            );
          }
        }
        expect(faults, isEmpty, reason: faults.join('\n'));
      });
    }
  }
}
