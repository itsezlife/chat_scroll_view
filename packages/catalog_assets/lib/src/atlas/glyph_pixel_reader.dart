import 'dart:typed_data';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';

/// Reads the pixels a [GlyphRasteriser] draws for one glyph: the rendering
/// half of the art fingerprint, which only needs "what do these glyphs look
/// like", not a page.
///
/// It draws the glyph filling a [size] px square on the root isolate and
/// reads the image back as RGBA8888, so a caller paces it itself (one glyph
/// per frame; see `computeGlyphArtFingerprint`). It is the same rasteriser the
/// bake uses, so the fingerprint changes exactly when the baked art would.
final class GlyphPixelReader {
  /// Creates a reader drawing with [rasteriser] into [size] px squares.
  GlyphPixelReader(this._rasteriser, {this.size = 48})
    : assert(size > 0, 'size must be positive');

  final GlyphRasteriser _rasteriser;

  /// Edge of the square the glyph is drawn into, in pixels.
  final int size;

  /// The pixels of [glyph]: `size * size * 4` bytes.
  Future<Uint8List> pixelsOf(String glyph) async {
    final recorder = PictureRecorder();
    _rasteriser.paint(
      Canvas(recorder),
      glyph,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    try {
      final data = await image.toByteData();
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
