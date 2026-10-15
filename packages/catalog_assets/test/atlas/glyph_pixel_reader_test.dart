import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads back what the rasteriser drew, at the size asked', () async {
    final reader = GlyphPixelReader(FakeGlyphRasteriser(), size: 8);

    final pixels = await reader.pixelsOf('x');

    expect(pixels.length, 8 * 8 * 4);
    final colour = FakeGlyphRasteriser.colorFor('x');
    // The fake fills the whole square: the first pixel is its colour.
    expect(pixels.sublist(0, 4), [
      (colour.r * 255).round(),
      (colour.g * 255).round(),
      (colour.b * 255).round(),
      255,
    ]);
  });

  test('another glyph reads back as other pixels', () async {
    final reader = GlyphPixelReader(FakeGlyphRasteriser(), size: 8);

    expect(await reader.pixelsOf('x'), isNot(await reader.pixelsOf('y')));
  });
}
