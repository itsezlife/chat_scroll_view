import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/paint/lottie_animation_paintable.dart';
import 'package:lottie_decoder/src/paint/lottie_still_paintable.dart';
import 'package:lottie_decoder/src/playback/lottie_frame_scheduler.dart';
import 'package:lottie_native/lottie_native.dart';

/// Decodes an encoded still image (the thumbnail of an animation) into an
/// image; `ui.decodeImageFromList` by default.
typedef LottieImageDecoder = Future<ui.Image> Function(Uint8List bytes);

/// Turns premultiplied RGBA [pixels] of [width] x [height] into an image;
/// `ui.decodeImageFromPixels` by default. It copies [pixels] before the
/// future completes: the caller frees the buffer right after.
typedef LottiePixelUploader =
    Future<ui.Image> Function(Uint8List pixels, int width, int height);

Future<ui.Image> _imageFromList(Uint8List bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, completer.complete);
  return completer.future;
}

Future<ui.Image> _imageFromPixels(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// The [Decoder] of the vector-animation media form: Lottie files, parsed and
/// drawn by a [LottieEngine] and played through a [LottieFrameScheduler].
///
/// | Request | Reports |
/// | --- | --- |
/// | a thumbnail (an ordinary image, not Lottie) | `AssetStage.placeholder`, a still |
/// | content, first frame only | `AssetStage.firstFrame`, a still |
/// | content, full | `firstFrame` (a still), then `full` (a [LottieAnimationPaintable], animated tier) |
///
/// Frame 0 is drawn at the spec's pixel size (the longer side capped at
/// `LottieRenderJob.maxEdge`) into a temporary native buffer, not into an
/// atlas slot: the pool may be full, and the still must exist whatever it
/// answers.
///
/// ## What an entry costs
///
/// The `full` stage reports the first frame (`width * height * 4`) plus four
/// times the encoded size for the parsed model, the estimate the web client
/// uses. The handle's real footprint lives in the native library and is not
/// visible here.
///
/// ## Above the largest size class
///
/// A spec whose longer side is over `LottieRenderJob.maxEdge` (512, the
/// largest size class of the pool) does not animate: the reference clients
/// skip the frame cache and cap the render at 512, so here the still is
/// reported as `firstFrame` and again as `full`, and the handle is freed
/// at once.
///
/// ## Handles
///
/// A handle belongs to the decode until a [LottieAnimationPaintable] takes it
/// over; from then on disposing the paintable frees it. A first-frame-only
/// decode, a failure and a cancel free it themselves, and never also hand it
/// to a paintable. Files with image or text layers still decode:
/// `LottieInfo.features` is informational and the host decides what to say.
///
/// A host registers the decoder only after its engine is up; see the package
/// README for the recipe.
final class LottieDecoder implements Decoder {
  /// Creates a decoder that draws with [engine] and plays through [scheduler].
  ///
  /// [decodeImage] and [uploadPixels] are the two steps that need the
  /// engine's image machinery; tests replace them.
  LottieDecoder({
    required LottieEngine engine,
    required LottieFrameScheduler scheduler,
    LottieImageDecoder decodeImage = _imageFromList,
    LottiePixelUploader uploadPixels = _imageFromPixels,
  }) : _engine = engine,
       _scheduler = scheduler,
       _decodeImage = decodeImage,
       _uploadPixels = uploadPixels;

  final LottieEngine _engine;
  final LottieFrameScheduler _scheduler;
  final LottieImageDecoder _decodeImage;
  final LottiePixelUploader _uploadPixels;

  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) {
    final task = _LottieDecode(this, request, progress);
    unawaited(task.run());
    return task;
  }
}

/// One decode, from encoded data to the reported stage.
final class _LottieDecode implements AssetTask {
  _LottieDecode(this._owner, this._request, this._progress);

  final LottieDecoder _owner;
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
    FetchedFile(:final path) => File(path).readAsBytes(),
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
      LottieStillPaintable(image),
      bytes: image.width * image.height * 4,
    );
  }

  Future<void> _content() async {
    final Uint8List bytes;
    final LottieLoadResult loaded;
    try {
      bytes = await _bytes();
      loaded = await _owner._engine.load(bytes);
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
      return;
    }
    // Cancelled while the engine parsed: a handle that arrives now is ours to
    // free, nobody else knows it.
    if (_cancelled) {
      if (loaded is LottieLoaded) _release(loaded.handle);
      return;
    }
    if (loaded is LottieRejected) {
      _fail(
        FormatException('The Lottie file was rejected: ${loaded.reason.name}'),
        StackTrace.current,
      );
      return;
    }
    final LottieLoaded(:handle, :info) = loaded as LottieLoaded;
    final spec = _request.spec;
    final edge = math.min(
      math.max(spec.pixelWidth, spec.pixelHeight),
      LottieRenderJob.maxEdge,
    );
    final width = _scaled(info.width, info, edge);
    final height = _scaled(info.height, info, edge);
    final ui.Image image;
    try {
      image = await _renderFirstFrame(handle, width, height);
    } on Object catch (error, stackTrace) {
      _release(handle);
      _fail(error, stackTrace);
      return;
    }
    if (_cancelled) {
      image.dispose();
      _release(handle);
      return;
    }
    // Outside the try above: from here the image and the handle belong to the
    // paintables handed over.
    final frameBytes = width * height * 4;
    // The still of the final stage is a second reference to the pixels, taken
    // before the first stage goes out: the cache may dispose that one at once.
    final finalImage = spec.variant == AssetVariant.full ? image.clone() : null;
    final animates =
        spec.variant == AssetVariant.full &&
        math.max(spec.pixelWidth, spec.pixelHeight) <= LottieRenderJob.maxEdge;
    if (!animates) {
      _release(handle);
      _progress.advance(
        AssetStage.firstFrame,
        LottieStillPaintable(image),
        bytes: frameBytes,
      );
      // Above the cap the still is the final picture too; each stage owns its
      // own reference to the pixels.
      if (finalImage != null) {
        _progress.advance(
          AssetStage.full,
          LottieStillPaintable(finalImage),
          bytes: frameBytes,
        );
      }
      return;
    }
    final key = Object();
    _progress
      ..advance(
        AssetStage.firstFrame,
        LottieStillPaintable(image),
        bytes: frameBytes,
      )
      ..advance(
        AssetStage.full,
        LottieAnimationPaintable(
          key: key,
          handle: handle,
          info: info,
          firstFrame: finalImage!,
          scheduler: _owner._scheduler,
          renderEdge: edge,
          onDispose: () => _release(handle),
        ),
        bytes: frameBytes + 4 * bytes.length,
        tier: AssetTier.animated,
      );
  }

  Future<ui.Image> _renderFirstFrame(
    LottieHandle handle,
    int width,
    int height,
  ) async {
    final buffer = calloc<Uint8>(width * height * 4);
    try {
      final statuses = await _owner._engine.renderBatch([
        LottieEngineJob(
          handle: handle,
          frame: 0,
          width: width,
          height: height,
          address: buffer.address,
          strideBytes: width * 4,
        ),
      ]);
      if (statuses.single != LottieRenderStatus.ok) {
        throw StateError(
          'The first frame did not render: ${statuses.single.name}',
        );
      }
      return await _owner._uploadPixels(
        buffer.asTypedList(width * height * 4),
        width,
        height,
      );
    } finally {
      calloc.free(buffer);
    }
  }

  void _release(LottieHandle handle) {
    unawaited(
      _owner._engine
          .dispose(handle)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              // A closed engine already freed every handle it issued: the
              // host shut down while this decode was ending, and there is
              // nothing left to free. Any other failure is a real one.
              if (error is LottieEngineClosed) return;
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stackTrace,
                  library: 'lottie_decoder',
                  context: ErrorDescription('while disposing a Lottie handle'),
                ),
              );
            },
          ),
    );
  }

  static int _scaled(int side, LottieInfo info, int edge) =>
      math.max(1, (side * edge / math.max(info.width, info.height)).round());
}
