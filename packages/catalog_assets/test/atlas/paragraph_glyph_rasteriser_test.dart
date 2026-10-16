/// What the system rasteriser draws for a glyph its font cannot form.
///
/// **Seam:** [ParagraphGlyphRasteriser] read back through a
/// [GlyphPixelReader]. The test font draws every code point as its own square,
/// so a joined sequence the font has no single glyph for (as a phone's font
/// lacks 👁️‍🗨️) lays out as several squares, the way a real font falls back to
/// drawing the parts side by side.
library;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

bool _inked(List<int> pixels) {
  for (var i = 3; i < pixels.length; i += 4) {
    if (pixels[i] != 0) return true;
  }
  return false;
}

void main() {
  final reader = GlyphPixelReader(ParagraphGlyphRasteriser());

  test('draws a glyph the font forms', () async {
    expect(_inked(await reader.pixelsOf('\u{1F600}')), isTrue);
  });

  test('draws nothing for a sequence that does not form one glyph, rather '
      'than its parts wrapped and cut by the cell', () async {
    expect(_inked(await reader.pixelsOf('\u{1F600}‍\u{1F34E}')), isFalse);
  });
}
