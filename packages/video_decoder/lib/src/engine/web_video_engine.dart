import 'dart:async';
import 'dart:typed_data';

import 'package:video_decoder/src/engine/video_element_port.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_decoder/src/engine/video_frame_pixels.dart';
import 'package:video_native/video_native.dart';

/// Makes the port for one video's [bytes], drawing frames at [width] by
/// [height]. The browser's is `JsVideoElementPort.create`.
typedef VideoElementPortFactory =
    VideoElementPort Function(
      Uint8List bytes, {
      required int width,
      required int height,
    });

/// A [VideoEngine] over the browser's own video decoding: each clip is a
/// hidden `<video>` element (behind a [VideoElementPort]) whose presented
/// frames are drawn to a canvas and copied out.
///
/// ## What differs from the native engines
///
/// - **Real time.** The browser decides when a frame is presented, not the
///   caller: [nextFrame] waits for the next presented frame, so a slow caller
///   skips frames instead of seeing them all. `VideoFrameScheduler` already
///   decodes ahead of the clock and drops what it is too late for, so it
///   needs nothing else. Waiting is unbounded (a hidden tab presents
///   nothing); [dispose] is what bounds it.
/// - **Alpha** is whatever the browser decodes. A browser without WebM alpha
///   draws the video opaque, and `VideoInfo.hasAlpha` then reads false (the
///   port looks at the first frame, see `VideoFramePixels.hasTransparency`).
/// - **No frame rate**: `VideoInfo.frameRate` is 0, the browser does not say.
/// - **An element cap.** Browsers allow a limited number of live media
///   elements; past [maxElements] [open] answers
///   `VideoRejection.limitExceeded` instead of making an element that would
///   stall the others.
///
/// No code here touches the browser: the port does. That keeps the rules
/// above testable on the VM (`FakeVideoElements`).
final class WebVideoEngine implements VideoEngine {
  /// Creates an engine whose clips are made by [createPort].
  ///
  /// [maxElements] caps the clips open at once. [metadataTimeout] bounds the
  /// wait for a video to become ready; a video that does not is taken as one
  /// the browser cannot play. [disposeTimeout] bounds how long [dispose] lets
  /// requests under way finish.
  WebVideoEngine({
    required VideoElementPortFactory createPort,
    this.maxElements = defaultMaxElements,
    this.metadataTimeout = const Duration(seconds: 10),
    this.disposeTimeout = const Duration(seconds: 2),
  }) : _createPort = createPort;

  /// The default cap on open clips: well under what browsers hold alive
  /// before they stop decoding the oldest elements.
  static const defaultMaxElements = 16;

  final VideoElementPortFactory _createPort;

  /// The most clips open at once.
  final int maxElements;

  /// How long [open] waits for a video to become ready.
  final Duration metadataTimeout;

  /// How long [dispose] lets requests under way finish.
  final Duration disposeTimeout;

  final _clips = <int, _OpenClip>{};
  final _inflight = <Future<void>>{};
  var _reserved = 0;
  var _nextId = 1;
  Future<void>? _disposing;

  bool get _disposed => _disposing != null;

  void _requireOpen() {
    if (_disposed) throw VideoEngineClosed();
  }

  // --- Opening and closing -------------------------------------------------

  @override
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    _requireOpen();
    if (width <= 0 || height <= 0) {
      return const VideoClipRejected(VideoRejection.badSize);
    }
    // Reserved before the first await so concurrent opens cannot all pass.
    if (_reserved >= maxElements) {
      return const VideoClipRejected(VideoRejection.limitExceeded);
    }
    _reserved++;
    VideoElementPort? port;
    try {
      port = _createPort(bytes, width: width, height: height);
      final metadata = await port.loadMetadata().timeout(metadataTimeout);
      if (_disposed) throw VideoEngineClosed();
      final clip = VideoClip(
        id: _nextId++,
        info: VideoInfo(
          width: metadata.width,
          height: metadata.height,
          duration: metadata.duration,
          frameRate: 0,
          hasAlpha: metadata.hasAlpha,
        ),
        width: width,
        height: height,
      );
      _clips[clip.id] = _OpenClip(clip, port);
      return VideoClipOpened(clip);
    } on Object catch (error) {
      _reserved--;
      port?.dispose();
      // Disposed while opening: the caller learns what a late open learns.
      if (error is VideoEngineClosed) rethrow;
      return VideoClipRejected(switch (error) {
        VideoElementFailure(:final reason) => reason,
        // A video that never became ready is one the browser cannot play.
        TimeoutException() => VideoRejection.unsupported,
        _ => VideoRejection.internal,
      });
    }
  }

  @override
  Future<void> close(VideoClip clip) async {
    final open = _clips.remove(clip.id);
    if (open == null) return;
    _reserved--;
    open.port.dispose();
  }

  // --- Frames --------------------------------------------------------------

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    _requireOpen();
    final open = _clips[clip.id];
    if (open == null) {
      return const VideoFrameResult(VideoFrameStatus.badArgument);
    }
    if (destination.length < clip.frameBytes) {
      return const VideoFrameResult(VideoFrameStatus.badSize);
    }
    return _serve(open, () => _frame(open, destination));
  }

  Future<VideoFrameResult> _frame(_OpenClip open, Uint8List destination) async {
    // Closed while queued. An engine disposed while queued still runs the
    // request: dispose bounds it, and a late frame is dropped below.
    if (_clips[open.clip.id] != open) {
      return const VideoFrameResult(VideoFrameStatus.badArgument);
    }
    final VideoElementFrameResult result;
    try {
      result = await open.port.nextFrame();
    } on Object {
      // The browser could not draw, or the element went away under us; the
      // caller sees a failed frame and may rewind.
      return const VideoFrameResult(VideoFrameStatus.failed);
    }
    switch (result) {
      case VideoElementEnded():
        return const VideoFrameResult(VideoFrameStatus.endOfStream);
      case VideoElementFrame(:final rgba, :final ptsMs):
        // Nothing is written once the clip or the engine is gone: the caller
        // may already have reused the buffer.
        if (!_isOpen(open) || rgba.length < open.clip.frameBytes) {
          return const VideoFrameResult(VideoFrameStatus.failed);
        }
        VideoFramePixels.premultiplyRgbaIntoBgra(rgba, destination);
        return VideoFrameResult(VideoFrameStatus.frame, ptsMs);
    }
  }

  @override
  Future<bool> rewind(VideoClip clip) async {
    _requireOpen();
    final open = _clips[clip.id];
    if (open == null) return false;
    return _serve(open, () async {
      if (_clips[open.clip.id] != open) return false;
      try {
        await open.port.rewind();
        return true;
        // See _frame: any failure of the element is "cannot rewind".
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        return false;
      }
    });
  }

  bool _isOpen(_OpenClip open) => !_disposed && _clips[open.clip.id] == open;

  /// Runs [body] after the clip's earlier requests, so calls on one clip are
  /// served in the order made, and tracks it so [dispose] can wait for it.
  Future<T> _serve<T>(_OpenClip open, Future<T> Function() body) {
    final run = open.tail.then((_) => body());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    open.tail = done;
    _inflight.add(done);
    unawaited(done.whenComplete(() => _inflight.remove(done)));
    return run;
  }

  // --- Disposal ------------------------------------------------------------

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    // Requests under way get a bounded time: a frame is real time and a
    // hidden tab never presents one, so an unbounded wait could outlive the
    // page. What is left is cut off by releasing the elements, which fails it.
    await Future.wait(
      List.of(_inflight),
    ).then<void>((_) {}).timeout(disposeTimeout, onTimeout: () {});
    for (final open in _clips.values) {
      open.port.dispose();
    }
    _clips.clear();
    _reserved = 0;
  }
}

final class _OpenClip {
  _OpenClip(this.clip, this.port);

  final VideoClip clip;
  final VideoElementPort port;
  Future<void> tail = Future<void>.value();
}
