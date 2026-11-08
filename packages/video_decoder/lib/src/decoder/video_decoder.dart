import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_decoder/src/environment_specific/read_file_bytes.dart'
    as environment_specific;
import 'package:video_decoder/src/paint/video_animation_paintable.dart';
import 'package:video_decoder/src/paint/video_still_paintable.dart';
import 'package:video_decoder/src/playback/video_frame_scheduler.dart';
import 'package:video_decoder/src/renderer/video_frame_size.dart';
import 'package:video_native/video_native.dart';

/// Decodes an encoded still image (the thumbnail of a clip) into an image;
/// `MiniThumbnail.decode` by default: a few dozen pixels, blurred once.
typedef VideoImageDecoder = Future<ui.Image> Function(Uint8List bytes);

/// Turns premultiplied BGRA [pixels] of [width] x [height] into an image;
/// `ui.decodeImageFromPixels` as `bgra8888` by default.
typedef VideoPixelUploader =
    Future<ui.Image> Function(Uint8List pixels, int width, int height);

Future<ui.Image> _imageFromPixels(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

/// Why a clip did not decode: the binding refused the file.
///
/// The decode ends with `AssetProgress.fail` carrying this, so a host's
/// diagnostics can tell a file this build cannot play ([VideoRejection.unsupported])
/// from a damaged one. The leaf keeps its placeholder either way (ADR 020).
final class VideoDecodeRejected implements Exception {
  /// Creates the error for a file refused for [reason].
  const VideoDecodeRejected(this.reason);

  /// Why, as the binding reported it.
  final VideoRejection reason;

  @override
  String toString() => 'The video was rejected: ${reason.name}';
}

/// The [Decoder] of the video media form: GIFs and WebM / MP4 stickers,
/// decoded by a [VideoEngine] and played through a [VideoFrameScheduler].
///
/// | Request | Reports |
/// | --- | --- |
/// | a thumbnail (an ordinary image, not video) | `AssetStage.placeholder`, a still decoded small and blurred (`MiniThumbnail`) |
/// | content, first frame only | `AssetStage.firstFrame`, a still |
/// | content, full | `firstFrame` (a still), then `full` (a [VideoAnimationPaintable], animated tier) |
///
/// ## The size
///
/// Frames are decoded at the display size: the spec's longer side snapped up
/// to a size class of the video pool (64, 128, 256, 384, 512; never above the
/// largest), the clip's aspect kept. The engine scales to an exact size and
/// the aspect is known only after opening, so a clip is opened once at a
/// square of that edge, and again at the fitted size when it is not square
/// (the square one is closed first; the open only builds a scaler, no frame
/// is decoded).
///
/// ## What an entry costs
///
/// The `still` stage reports its `width * height * 4`; the `full` stage that
/// plus the encoded size (the engine keeps the file open). The decoded frames
/// the scheduler keeps ahead of the clock are not an entry's: they are bounded
/// by the scheduler's cap on advancing clips.
///
/// ## Clips
///
/// An open clip belongs to the decode until a [VideoAnimationPaintable] takes
/// it over; from then on disposing the paintable closes it. A first-frame-only
/// decode, a failure and a cancel close it themselves, and never also hand it
/// to a paintable.
///
/// A host registers the decoder only after its engine is up; see the package
/// README for the recipe.
final class VideoDecoder implements Decoder {
  /// Creates a decoder that decodes with [engine] and plays through
  /// [scheduler].
  ///
  /// [sizeClasses] must be the classes the scheduler's pool was built with
  /// (the default for `VideoFrameAtlas.create`). [decodeImage] and
  /// [uploadPixels] are the two steps that need the engine's image machinery;
  /// tests replace them.
  VideoDecoder({
    required VideoEngine engine,
    required VideoFrameScheduler scheduler,
    List<int> sizeClasses = VideoFrameSize.defaultClasses,
    VideoImageDecoder decodeImage = MiniThumbnail.decode,
    VideoPixelUploader uploadPixels = _imageFromPixels,
  }) : _engine = engine,
       _scheduler = scheduler,
       _sizeClasses = sizeClasses,
       _decodeImage = decodeImage,
       _uploadPixels = uploadPixels;

  final VideoEngine _engine;
  final VideoFrameScheduler _scheduler;
  final List<int> _sizeClasses;
  final VideoImageDecoder _decodeImage;
  final VideoPixelUploader _uploadPixels;

  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) {
    final task = _VideoDecode(this, request, progress);
    unawaited(task.run());
    return task;
  }
}

/// One decode, from encoded data to the reported stage.
final class _VideoDecode implements AssetTask {
  _VideoDecode(this._owner, this._request, this._progress);

  final VideoDecoder _owner;
  final DecodeRequest _request;
  final AssetProgress _progress;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  Future<void> run() async {
    switch (_request.part) {
      case FetchPart.thumbnail:
        await _thumbnail();
      case FetchPart.content:
        await _content();
    }
  }

  Future<Uint8List> _bytes() => switch (_request.content) {
    FetchedBytes(:final bytes) => Future.value(bytes),
    FetchedFile(:final path) => environment_specific.$readFileBytes(path),
  };

  void _fail(Object error, StackTrace stackTrace) {
    if (!_cancelled) {
      _progress.fail(error, stackTrace, AssetFailureKind.permanent);
    }
  }

  Future<void> _thumbnail() async {
    final ui.Image image;
    try {
      image = await _owner._decodeImage(await _bytes());
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
      return;
    }
    if (_cancelled) {
      image.dispose();
      return;
    }
    _progress.advance(
      AssetStage.placeholder,
      VideoStillPaintable(image),
      bytes: image.width * image.height * 4,
    );
  }

  Future<void> _content() async {
    final VideoClip clip;
    final Uint8List bytes;
    final Uint8List first;
    try {
      bytes = await _bytes();
      clip = await _open(bytes);
      try {
        first = await _firstFrame(clip);
      } on Object {
        _close(clip);
        rethrow;
      }
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
      return;
    }
    // Cancelled while the engine decoded: a clip that arrives now is ours to
    // close, nobody else knows it.
    if (_cancelled) {
      _close(clip);
      return;
    }
    final ui.Image image;
    try {
      image = await _owner._uploadPixels(first, clip.width, clip.height);
    } on Object catch (error, stackTrace) {
      _close(clip);
      _fail(error, stackTrace);
      return;
    }
    if (_cancelled) {
      image.dispose();
      _close(clip);
      return;
    }
    // Outside the try above: from here the image and the clip belong to the
    // paintables handed over.
    final frameBytes = clip.frameBytes;
    if (_request.spec.variant == AssetVariant.firstFrame) {
      _close(clip);
      _progress.advance(
        AssetStage.firstFrame,
        VideoStillPaintable(image),
        bytes: frameBytes,
      );
      return;
    }
    // The animation's still is a second reference to the pixels, taken before
    // the first stage goes out: the cache may dispose that one at once.
    final animationStill = image.clone();
    _progress
      ..advance(
        AssetStage.firstFrame,
        VideoStillPaintable(image),
        bytes: frameBytes,
      )
      ..advance(
        AssetStage.full,
        VideoAnimationPaintable(
          key: Object(),
          clip: clip,
          firstFrame: animationStill,
          scheduler: _owner._scheduler,
          onDispose: () => _close(clip),
        ),
        bytes: frameBytes + bytes.length,
        tier: AssetTier.animated,
      );
  }

  /// Opens [bytes] at the size class the spec snaps to, aspect kept.
  Future<VideoClip> _open(Uint8List bytes) async {
    final spec = _request.spec;
    final edge = VideoFrameSize.edgeFor(
      math.max(spec.pixelWidth, spec.pixelHeight),
      classes: _owner._sizeClasses,
    );
    final probe = await _openAt(bytes, edge, edge);
    final fitted = VideoFrameSize.fitting(probe.info, edge);
    if (fitted.width == probe.width && fitted.height == probe.height) {
      return probe;
    }
    _close(probe);
    return _openAt(bytes, fitted.width, fitted.height);
  }

  Future<VideoClip> _openAt(Uint8List bytes, int width, int height) async {
    final opened = await _owner._engine.open(
      bytes,
      width: width,
      height: height,
    );
    return switch (opened) {
      VideoClipOpened(:final clip) => clip,
      VideoClipRejected(:final reason) => throw VideoDecodeRejected(reason),
    };
  }

  Future<Uint8List> _firstFrame(VideoClip clip) async {
    final pixels = Uint8List(clip.frameBytes);
    final result = await _owner._engine.nextFrame(clip, destination: pixels);
    if (result.status != VideoFrameStatus.frame) {
      throw StateError(
        'The first frame did not decode: ${result.status.name}.',
      );
    }
    return pixels;
  }

  void _close(VideoClip clip) {
    unawaited(
      _owner._engine
          .close(clip)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              // A closed engine already freed every clip it issued: the host
              // shut down while this decode was ending. Any other failure is
              // a real one.
              if (error is VideoEngineClosed) return;
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stackTrace,
                  library: 'video_decoder',
                  context: ErrorDescription('while closing a video clip'),
                ),
              );
            },
          ),
    );
  }
}
