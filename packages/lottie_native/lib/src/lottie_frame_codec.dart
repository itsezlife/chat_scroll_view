import 'dart:ffi';
import 'dart:typed_data';

/// A rectangle of page memory the frame codec reads or writes.
final class LottieFrameRegion {
  /// Creates a region.
  const LottieFrameRegion({
    required this.target,
    required this.width,
    required this.height,
    required this.strideBytes,
  });

  /// The largest region edge, in pixels, the codec accepts; the same cap as
  /// a render slot.
  static const int maxEdge = 512;

  /// The top-left pixel, premultiplied RGBA bytes `[R, G, B, A]`.
  final Pointer<Uint8> target;

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// The distance in bytes between the starts of two rows.
  final int strideBytes;
}

/// The frame cache's lz4 codec over regions of page memory.
abstract interface class LottieFrameCodec {
  /// Whether the codec can run; decided once at construction.
  ///
  /// [compress] and [decompress] on one that is not throw a [StateError].
  bool get isAvailable;

  /// The compressed bytes of [region], or null when the region is rejected
  /// (a zero edge, an edge over [LottieFrameRegion.maxEdge], a stride under
  /// the row width). Reads only the region's own bytes.
  Uint8List? compress(LottieFrameRegion region);

  /// Writes [data] into [region] and returns true; false for corrupt data,
  /// data of another size or a rejected region, in which case no byte of
  /// the region is touched. Never throws for data.
  bool decompress(Uint8List data, LottieFrameRegion region);
}
