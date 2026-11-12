import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:video_decoder/src/engine/video_element_port.dart';
import 'package:video_decoder/src/engine/video_frame_pixels.dart';
import 'package:video_native/video_native.dart';
import 'package:web/web.dart' as web;

/// A [VideoElementPort] over a hidden, muted `<video>` element fed a Blob
/// URL, drawn to a canvas of the target size.
///
/// Compile-checked by `web_compile_test` and run in a headless browser by
/// hand (see the package README); nothing on the VM runs it. The engine's
/// rules around it are tested over `FakeVideoElements`.
///
/// ## How a frame is taken
///
/// The element plays in real time. [nextFrame] waits for the next presented
/// frame with `requestVideoFrameCallback`, or, in a browser without it, for
/// an animation frame in which `currentTime` moved. It then draws the element
/// scaled to the canvas (not letterboxed) and reads the pixels back with
/// `getImageData`, which returns straight RGBA: premultiplying is the
/// engine's job.
///
/// An element that nobody asks frames from is paused after [idlePause], so a
/// clip scrolled out of use does not decode on in the background.
final class JsVideoElementPort implements VideoElementPort {
  JsVideoElementPort._(this._video, this._canvas, this._context, this._url);

  /// Makes the port for [bytes] at [width] by [height]; the factory a
  /// `WebVideoEngine` takes.
  factory JsVideoElementPort.create(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: _mimeOf(bytes)),
    );
    final url = web.URL.createObjectURL(blob);
    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..muted = true
      ..defaultMuted = true
      ..playsInline = true
      ..loop = false
      ..preload = 'auto'
      // Attached (some browsers do not decode a detached element) but out of
      // sight and out of the way of hit testing.
      ..style.cssText =
          'position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;'
          'pointer-events:none;visibility:hidden';
    video.setAttribute('aria-hidden', 'true');
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;
    final context =
        canvas.getContext(
              '2d',
              <String, Object>{'willReadFrequently': true}.jsify(),
            )
            as web.CanvasRenderingContext2D;
    web.document.body!.append(video);
    return JsVideoElementPort._(video, canvas, context, url).._load();
  }

  /// How long an element keeps playing with nobody asking for frames.
  static const idlePause = Duration(milliseconds: 300);

  final web.HTMLVideoElement _video;
  final web.HTMLCanvasElement _canvas;
  final web.CanvasRenderingContext2D _context;
  final String _url;
  final _ready = Completer<VideoElementMetadata>();
  // Each waiting request's way to settle, so a failure or a release can end it.
  final _pending = <Completer<Object?>, void Function(Object?)>{};
  Timer? _idle;
  var _disposed = false;

  /// The container by its magic bytes: a blob without a type is sniffed by
  /// some browsers and refused by others. Anything unknown gets none.
  static String _mimeOf(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x1A &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xDF &&
        bytes[3] == 0xA3) {
      return 'video/webm';
    }
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'video/mp4';
    }
    return '';
  }

  // --- Metadata ------------------------------------------------------------

  void _load() {
    _video
      ..addEventListener('loadeddata', ((web.Event _) => _onReady()).toJS)
      ..addEventListener('error', ((web.Event _) => _onError()).toJS)
      ..src = _url;
  }

  void _onReady() {
    if (_ready.isCompleted) return;
    try {
      final width = _video.videoWidth;
      final height = _video.videoHeight;
      if (width <= 0 || height <= 0) {
        // Audio only, or nothing drawable.
        _ready.completeError(
          const VideoElementFailure(VideoRejection.unsupported, 'no video'),
        );
        return;
      }
      final seconds = _video.duration;
      _ready.complete(
        VideoElementMetadata(
          width: width,
          height: height,
          duration: seconds.isFinite
              ? Duration(milliseconds: (seconds * 1000).round())
              : null,
          // A browser without WebM alpha draws the video opaque, so this is
          // false there and the clip is shown without transparency.
          hasAlpha: VideoFramePixels.hasTransparency(_read()),
        ),
      );
    } on Object catch (error) {
      _ready.completeError(
        VideoElementFailure(VideoRejection.internal, '$error'),
      );
    }
  }

  void _onError() {
    final code = _video.error?.code ?? 0;
    final failure = VideoElementFailure(switch (code) {
      // MEDIA_ERR_DECODE: the container was read and the stream is damaged.
      3 => VideoRejection.malformed,
      // MEDIA_ERR_SRC_NOT_SUPPORTED: bytes that are no container, or a
      // codec this browser lacks; the element does not say which.
      4 => VideoRejection.unsupported,
      _ => VideoRejection.internal,
    }, _video.error?.message ?? '');
    if (!_ready.isCompleted) _ready.completeError(failure);
    _fail(failure);
  }

  @override
  Future<VideoElementMetadata> loadMetadata() => _ready.future;

  // --- Frames --------------------------------------------------------------

  @override
  Future<VideoElementFrameResult> nextFrame() {
    if (_disposed) {
      return Future.error(const VideoElementFailure(VideoRejection.internal));
    }
    _idle?.cancel();
    if (_video.ended) return Future.value(const VideoElementEnded());
    final done = Completer<Object?>();
    var lastTime = _video.currentTime;
    final wasPaused = _video.paused;

    late final JSFunction onEnded;
    int? callback;
    void finish(Object? value) {
      _video.removeEventListener('ended', onEnded);
      if (callback != null) _video.cancelVideoFrameCallback(callback!);
      _pending.remove(done);
      if (!done.isCompleted) done.complete(value);
    }

    onEnded = ((web.Event _) => finish(const VideoElementEnded())).toJS;
    _video.addEventListener('ended', onEnded);
    done.future.ignore();
    _pending[done] = finish;

    void present(double mediaTime) {
      try {
        finish(VideoElementFrame(_read(), (mediaTime * 1000).round()));
      } on Object catch (error) {
        finish(VideoElementFailure(VideoRejection.internal, '$error'));
      }
      _armIdle();
    }

    void waitForFrame() {
      if (done.isCompleted) return;
      if (_hasFrameCallback) {
        callback = _video.requestVideoFrameCallback(
          ((JSNumber now, JSObject metadata) {
            callback = null;
            present(_mediaTimeOf(metadata));
          }).toJS,
        );
      } else {
        // No requestVideoFrameCallback: an animation frame in which the clock
        // of the element moved is a frame the element presented.
        void tick(JSNumber _) {
          if (done.isCompleted) return;
          if (_video.currentTime != lastTime || _video.ended) {
            lastTime = _video.currentTime;
            if (_video.ended) return finish(const VideoElementEnded());
            return present(lastTime);
          }
          web.window.requestAnimationFrame(tick.toJS);
        }

        web.window.requestAnimationFrame(tick.toJS);
      }
    }

    waitForFrame();
    if (wasPaused) {
      _video.play().toDart.catchError((Object error) {
        finish(VideoElementFailure(VideoRejection.internal, '$error'));
        return null;
      });
    }
    return done.future.then((value) {
      if (value is VideoElementFailure) throw value;
      return value! as VideoElementFrameResult;
    });
  }

  bool get _hasFrameCallback =>
      (_video as JSObject).has('requestVideoFrameCallback');

  static double _mediaTimeOf(JSObject metadata) =>
      (metadata['mediaTime'] as JSNumber?)?.toDartDouble ?? 0;

  /// Draws the element at the canvas size and returns the straight RGBA.
  Uint8List _read() {
    final width = _canvas.width;
    final height = _canvas.height;
    _context
      ..clearRect(0, 0, width, height)
      ..drawImage(_video, 0, 0, width, height);
    final data = _context.getImageData(0, 0, width, height).data.toDart;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(idlePause, () {
      if (!_disposed) _video.pause();
    });
  }

  // --- Rewind and release --------------------------------------------------

  @override
  Future<void> rewind() async {
    if (_disposed) throw const VideoElementFailure(VideoRejection.internal);
    _idle?.cancel();
    _video.pause();
    if (_video.currentTime == 0 && !_video.ended) return;
    final seeked = Completer<void>();
    late final JSFunction onSeeked;
    onSeeked = ((web.Event _) {
      _video.removeEventListener('seeked', onSeeked);
      if (!seeked.isCompleted) seeked.complete();
    }).toJS;
    _video.addEventListener('seeked', onSeeked);
    _video.currentTime = 0;
    try {
      await seeked.future.timeout(const Duration(seconds: 2));
    } finally {
      _video.removeEventListener('seeked', onSeeked);
    }
  }

  void _fail(VideoElementFailure failure) {
    for (final finish in List.of(_pending.values)) {
      finish(failure);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idle?.cancel();
    _fail(const VideoElementFailure(VideoRejection.internal, 'disposed'));
    if (!_ready.isCompleted) {
      _ready.completeError(
        const VideoElementFailure(VideoRejection.internal, 'disposed'),
      );
    }
    _ready.future.ignore();
    _video
      ..pause()
      ..removeAttribute('src')
      ..load()
      ..remove();
    web.URL.revokeObjectURL(_url);
  }
}
