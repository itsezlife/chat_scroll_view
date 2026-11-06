import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Turns the bytes of a small preview still into the picture a surface shows
/// under content that is still loading: tiny, and blurred once, here.
///
/// The reference client keeps a thumbnail of at most about 40 pixels a side and
/// stack-blurs it at radius 3 when it decodes it; the surface then stretches
/// the tiny bitmap over the whole box with bilinear filtering. This does the
/// same, so painting it is one image draw per frame, never a blur: the cost of
/// the blur is paid once per thumbnail, on a bitmap of at most [maxEdge] pixels.
abstract final class MiniThumbnail {
  /// The longer side the thumbnail is decoded to; a smaller still is kept as
  /// it is.
  static const int maxEdge = 40;

  /// The reference client's stack-blur radius (`Utilities.blurBitmap`, 3).
  static const int stackBlurRadius = 3;

  /// The Gaussian sigma whose spread equals a stack blur of
  /// [stackBlurRadius]: the stack kernel is triangular, and a triangle of
  /// radius `r` has variance `r * (r + 2) / 6`.
  static final double sigma = math.sqrt(
    stackBlurRadius * (stackBlurRadius + 2) / 6,
  );

  /// Decodes [bytes], an encoded still (JPEG, PNG, WebP, or the first frame of
  /// a GIF), to at most [maxEdge] pixels on its longer side, aspect kept, and
  /// blurs it. The caller owns the image.
  ///
  /// Fails when [bytes] are not an image the engine reads.
  static Future<ui.Image> decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final longer = math.max(descriptor.width, descriptor.height);
        final scale = longer > maxEdge ? maxEdge / longer : 1.0;
        final width = math.max(1, (descriptor.width * scale).round());
        final height = math.max(1, (descriptor.height * scale).round());
        final codec = await descriptor.instantiateCodec(
          targetWidth: width,
          targetHeight: height,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            return await _blurred(frame.image);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  static Future<ui.Image> _blurred(ui.Image source) {
    final recorder = ui.PictureRecorder();
    // Clamped edges: the border keeps its colour instead of fading to clear.
    ui.Canvas(recorder).drawImage(
      source,
      ui.Offset.zero,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: ui.TileMode.clamp,
        ),
    );
    final picture = recorder.endRecording();
    return picture
        .toImage(source.width, source.height)
        .whenComplete(picture.dispose);
  }
}
