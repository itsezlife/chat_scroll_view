/// The rig of the flicker diagnosis (ticket 55): the real video pipeline above
/// a scripted engine, a manual clock and a page upload whose latency a test
/// controls.
///
/// Real: [VideoFrameScheduler], [VideoAnimationPaintable],
/// [VideoStillPaintable], `FrameAtlas` (pool, page memory, page images),
/// `VideoFrameRenderer`, `PlaybackClock`. Scripted: the engine (pixels name the
/// clip and the frame), the upload of a page (an image that remembers the bytes
/// it was made from, completed when the test says), time.
///
/// A pixel is BGRA `[frame, clip tag, 0, 255]`, so anything drawn from a page
/// can be traced to the clip and the frame it shows, or to nothing (alpha 0).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

/// The size of every clip: the smallest pool class, four cells a page.
const int clipEdge = 64;

/// What a drawn pixel of a page says.
typedef PixelProbe = ({int alpha, int tag, int frame});

/// A page image's bytes as they were when it was uploaded.
final class PageSnapshot {
  PageSnapshot(this.bytes, this.side);

  final Uint8List bytes;
  final int side;

  /// The pixel at the centre of [source].
  PixelProbe probe(ui.Rect source) {
    final x = source.center.dx.floor().clamp(0, side - 1);
    final y = source.center.dy.floor().clamp(0, side - 1);
    final at = (y * side + x) * 4;
    return (alpha: bytes[at + 3], tag: bytes[at + 1], frame: bytes[at]);
  }
}

/// Page uploads that finish [latencySteps] steps after they started.
///
/// The engine's `decodeImageFromPixels` finishes on a later frame; the fake
/// does the same, deterministically.
final class PageUploads {
  PageUploads({this.latencySteps = 0});

  /// Steps an upload takes; zero finishes it at once.
  int latencySteps;

  int _step = 0;
  final List<({int at, Completer<ui.Image> done, ui.Image image})> _pending =
      [];

  /// What each uploaded image was made from.
  final Map<ui.Image, PageSnapshot> snapshots =
      HashMap<ui.Image, PageSnapshot>.identity();

  /// Uploads started.
  int started = 0;

  Future<ui.Image> upload(Uint8List pixels, int side) {
    started++;
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    snapshots[image] = PageSnapshot(Uint8List.fromList(pixels), side);
    if (latencySteps == 0) return Future.value(image);
    final done = Completer<ui.Image>();
    _pending.add((at: _step, done: done, image: image));
    return done.future;
  }

  /// Ends one step: finishes the uploads that have waited long enough.
  void endStep() {
    _step++;
    final due = [
      for (final p in _pending)
        if (_step - p.at >= latencySteps) p,
    ];
    for (final p in due) {
      _pending.remove(p);
      p.done.complete(p.image);
    }
  }
}

/// An engine whose clips are `frames` long, at 30 fps; every pixel of a frame
/// is `[frame, tag, 0, 255]`, the tag being the first byte of the file.
final class TaggedVideoEngine implements VideoEngine {
  TaggedVideoEngine({this.frames = 60});

  final int frames;
  final Map<int, ({int tag, int next})> _open = {};
  int _ids = 1;

  /// `nextFrame` calls answered.
  int decoded = 0;

  @override
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    final id = _ids++;
    _open[id] = (tag: bytes.first, next: 0);
    return VideoClipOpened(
      VideoClip(
        id: id,
        info: VideoInfo(
          width: width,
          height: height,
          duration: Duration(milliseconds: frames * 1000 ~/ 30),
          frameRate: 30,
          hasAlpha: false,
        ),
        width: width,
        height: height,
      ),
    );
  }

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    final state = _open[clip.id]!;
    if (state.next >= frames) {
      return const VideoFrameResult(VideoFrameStatus.endOfStream);
    }
    decoded++;
    _open[clip.id] = (tag: state.tag, next: state.next + 1);
    for (var at = 0; at < clip.frameBytes; at += 4) {
      destination[at] = state.next % 256;
      destination[at + 1] = state.tag;
      destination[at + 2] = 0;
      destination[at + 3] = 255;
    }
    return VideoFrameResult(
      VideoFrameStatus.frame,
      (state.next * 1000 / 30).round(),
    );
  }

  @override
  Future<bool> rewind(VideoClip clip) async {
    final state = _open[clip.id]!;
    _open[clip.id] = (tag: state.tag, next: 0);
    return true;
  }

  @override
  Future<void> close(VideoClip clip) async => _open.remove(clip.id);

  @override
  Future<void> dispose() async => _open.clear();
}

/// A frame the renderer copied into a page: when, for which clip, which frame.
typedef RenderedFrame = ({Duration at, int tag, int frame});

/// The video renderer, writing down every frame it copies.
final class _LoggingRenderer implements FrameRenderer {
  _LoggingRenderer(this._now, this.log);

  final Duration Function() _now;
  final List<RenderedFrame> log;
  final FrameRenderer _inner = const VideoFrameRenderer();

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    final held = await _inner.render(jobs, memory);
    for (final i in held) {
      final pixels = (jobs[i].source as VideoFrameSource).pixelsOf(
        jobs[i].frame,
      )!;
      log.add((at: _now(), tag: pixels[1], frame: pixels[0]));
    }
    return held;
  }
}

/// The whole pipeline over one scheduler, as the example app builds it: one
/// scheduler, one clock, one pool for the chat and the panel alike.
final class VideoRig {
  VideoRig({
    int? maxAdvancing,
    int latencySteps = 0,
    Duration idleRelease = const Duration(seconds: 1),
    int frames = 60,
  }) : uploads = PageUploads(latencySteps: latencySteps),
       engine = TaggedVideoEngine(frames: frames),
       ticks = ManualPlaybackTickSource(),
       timers = ManualRetentionTimers() {
    clock = PlaybackClock(ticks: ticks);
    scheduler = VideoFrameScheduler(
      engine: engine,
      atlas: FrameAtlas<Object>(
        renderer: _LoggingRenderer(() => now, rendered),
        memory: ListFramePageMemory(),
        budgetBytes: VideoFrameAtlas.defaultBudgetBytes,
        sizeClasses: VideoFrameSize.defaultClasses,
        upload: uploads.upload,
        forgetIdleFrames: true,
      ),
      clock: clock,
      maxAdvancing: maxAdvancing ?? VideoFrameScheduler.defaultMaxAdvancing,
      idleRelease: idleRelease,
      startTimer: timers.start,
    );
  }

  final PageUploads uploads;
  final TaggedVideoEngine engine;
  final ManualPlaybackTickSource ticks;
  final ManualRetentionTimers timers;
  late final PlaybackClock clock;
  late final VideoFrameScheduler scheduler;

  /// Every frame copied into a page, in order.
  final List<RenderedFrame> rendered = [];

  /// The frame timestamp of the last step.
  Duration now = Duration.zero;

  /// A solid image to stand in for a decoded still.
  static ui.Image solid() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    picture.dispose();
    return image;
  }

  /// A clip of [tag] and its paintable, as the decoder hands them over.
  Future<VideoAnimationPaintable> clip(int tag) async {
    final opened = await engine.open(
      Uint8List.fromList([tag]),
      width: clipEdge,
      height: clipEdge,
    );
    return VideoAnimationPaintable(
      key: Object(),
      clip: (opened as VideoClipOpened).clip,
      firstFrame: solid(),
      scheduler: scheduler,
    );
  }

  /// The context a binding of a looping GIF paints with.
  AssetPaintContext get context => AssetPaintContext(
    time: clock.now,
    loop: true,
    restFrame: AssetRestFrame.first,
  );

  /// One display frame: the clock ticks (the scheduler follows it), then the
  /// surfaces paint [painted] (each asks its paintable to advance), then the
  /// futures that were waiting run.
  Future<void> step({
    Iterable<AssetPaintable> painted = const [],
    Duration by = const Duration(milliseconds: 16),
    Future<void> Function()? flush,
  }) async {
    now += by;
    ticks.tick(now);
    for (final paintable in painted) {
      paintable.advancePlayback(context);
    }
    await (flush?.call() ?? Future<void>.delayed(Duration.zero));
    uploads.endStep();
    timers.elapse(by);
  }

  /// Frames copied for [tag] in `[from, to)`.
  int framesOf(int tag, Duration from, Duration to) =>
      rendered.where((r) => r.tag == tag && r.at >= from && r.at < to).length;

  /// The last time a frame of [tag] was copied, or null.
  Duration? lastFrameAt(int tag) {
    for (var i = rendered.length - 1; i >= 0; i--) {
      if (rendered[i].tag == tag) return rendered[i].at;
    }
    return null;
  }

  void dispose() {
    scheduler.dispose();
    clock.dispose();
  }
}
