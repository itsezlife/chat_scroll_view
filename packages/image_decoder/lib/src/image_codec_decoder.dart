import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:image_decoder/src/image_paintable.dart';

/// Decodes images with the engine's codecs, at the size of the spec.
///
/// The image is decoded to fit inside the spec's pixels, keeping its aspect
/// ratio and never larger than it is encoded, and painted centred in the
/// surface's rectangle. What it reports:
///
/// | Request | Reports |
/// | --- | --- |
/// | a thumbnail | the first frame, as `AssetStage.placeholder` |
/// | content, first frame only | the first frame, as `AssetStage.firstFrame` |
/// | content, one frame | the frame, as `AssetStage.full` |
/// | content, several frames | a playing image, as `AssetStage.full`, in the animated tier |
///
/// ## Frames are decoded as they are shown
///
/// A playing image keeps the codec and decodes one frame ahead of the one it
/// shows, instead of decoding every frame up front. Up front would cost every
/// frame's pixels for as long as the entry lives: a 100 px emoji of 90 frames
/// is 3.6 MB that way and about 80 KB this way, and a screenful of them would
/// not fit the animated budget. The price is a decode per shown frame, which
/// the engine does off the UI thread, as the reference clients do for
/// animated WebP and GIF.
///
/// There is no frame report before the full stage: the first frame and the
/// playing image exist at the same moment.
///
/// ## Not covered
///
/// Vector animations and video codecs are other media forms with adapters of
/// their own. Content in a file is read with `ImmutableBuffer.fromFilePath`,
/// which the web does not support; a fetcher for the web hands bytes.
final class ImageCodecDecoder implements Decoder {
  /// Creates a decoder. It keeps no state between requests.
  const ImageCodecDecoder();

  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) {
    final task = _DecodeTask(request, progress);
    unawaited(task.run());
    return task;
  }
}

/// One decode, from encoded data to the reported stage.
final class _DecodeTask implements AssetTask {
  _DecodeTask(this._request, this._progress);

  final DecodeRequest _request;
  final AssetProgress _progress;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  Future<void> run() async {
    final ui.Codec codec;
    final ui.FrameInfo first;
    ui.Codec? decoding;
    try {
      final buffer = await switch (_request.content) {
        FetchedBytes(:final bytes) => ui.ImmutableBuffer.fromUint8List(bytes),
        FetchedFile(:final path) => ui.ImmutableBuffer.fromFilePath(path),
      };
      // Cancelled while the data was read: no codec, no decoded frame.
      if (_cancelled) {
        buffer.dispose();
        return;
      }
      // Takes the buffer over and disposes it.
      decoding = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: _fitIn(_request.spec),
      );
      if (_cancelled) {
        decoding.dispose();
        return;
      }
      first = await decoding.getNextFrame();
      codec = decoding;
    } on Object catch (error, stackTrace) {
      decoding?.dispose();
      // Undecodable data stays undecodable, whatever the network does.
      if (!_cancelled) {
        _progress.fail(error, stackTrace, AssetFailureKind.permanent);
      }
      return;
    }
    if (_cancelled) {
      first.image.dispose();
      codec.dispose();
      return;
    }
    // Outside the try: from here the codec and the frame belong to the
    // paintable handed over, and an error the progress throws is not a
    // decode failure. Caught above, it would dispose what the cache now
    // owns, and the cache would dispose it again.
    _report(codec, first);
  }

  void _report(ui.Codec codec, ui.FrameInfo first) {
    final spec = _request.spec;
    final template = spec.decodeMode == AssetDecodeMode.template;
    final frameBytes = first.image.width * first.image.height * 4;
    final stage = switch ((_request.part, spec.variant)) {
      (FetchPart.thumbnail, _) => AssetStage.placeholder,
      (FetchPart.content, AssetVariant.firstFrame) => AssetStage.firstFrame,
      (FetchPart.content, AssetVariant.full) => AssetStage.full,
    };
    if (stage == AssetStage.full && codec.frameCount > 1) {
      _progress.advance(
        stage,
        PlayingImagePaintable(codec, first, template: template),
        // The frame shown and the one decoded ahead.
        bytes: frameBytes * 2,
        tier: AssetTier.animated,
      );
      return;
    }
    codec.dispose();
    _progress.advance(
      stage,
      StillImagePaintable(first.image, template: template),
      bytes: frameBytes,
    );
  }

  /// The decode size of an image that fits inside [spec], keeping its aspect
  /// ratio. An image already smaller than the spec is decoded as it is:
  /// scaling up at decode costs pixels and adds no detail.
  static ui.TargetImageSizeCallback _fitIn(AssetSpec spec) => (width, height) {
    final scale = math.min(
      1,
      math.min(spec.pixelWidth / width, spec.pixelHeight / height),
    );
    if (scale >= 1) return const ui.TargetImageSize();
    return ui.TargetImageSize(
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  };
}
