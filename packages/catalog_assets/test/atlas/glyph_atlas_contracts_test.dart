import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';

void main() {
  runGlyphRasteriserContract('FakeGlyphRasteriser', FakeGlyphRasteriser.new);
  runGlyphRasteriserContract(
    'ParagraphGlyphRasteriser',
    ParagraphGlyphRasteriser.new,
    glyphs: const ['A', '😀', '👨‍👩‍👧‍👦', '🇯🇵'],
  );
  runGlyphPageStoreContract('FakeGlyphPageStore', FakeGlyphPageStore.new);
}
