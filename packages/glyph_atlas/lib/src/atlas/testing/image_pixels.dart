import 'dart:typed_data';
import 'dart:ui';

/// Pixels of an [Image] read back to the CPU, for assertions on baked output.
final class ImagePixels {
  ImagePixels._(this.width, this.height, this._rgba);

  /// Reads [image] back (the handle is not disposed).
  static Future<ImagePixels> of(Image image) async {
    final data = await image.toByteData();
    return ImagePixels._(
      image.width,
      image.height,
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  final Uint8List _rgba;

  /// The colour at ([x], [y]); fully transparent outside the image.
  Color at(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return const Color(0x00000000);
    }
    final i = (y * width + x) * 4;
    return Color.fromARGB(_rgba[i + 3], _rgba[i], _rgba[i + 1], _rgba[i + 2]);
  }

  /// Whether any pixel in [rect] (clamped to the image) is not fully
  /// transparent.
  bool hasInk(Rect rect) {
    final left = rect.left.floor().clamp(0, width);
    final top = rect.top.floor().clamp(0, height);
    final right = rect.right.ceil().clamp(0, width);
    final bottom = rect.bottom.ceil().clamp(0, height);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (_rgba[(y * width + x) * 4 + 3] != 0) return true;
      }
    }
    return false;
  }
}
