import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _mebibyte = 1024 * 1024;

void main() {
  test('a catalogue of the current size bakes into three pages and 48 MiB', () {
    // Spec figures (baked emoji atlas): about 676 cells per page, three pages
    // for the current catalogue, about 48 MiB (64 MiB with mip levels).
    final glyphs = sampleGlyphCatalogue();
    final index = GlyphAtlasIndex(glyphs);

    expect(glyphs, hasLength(sampleCatalogueSize));
    expect(glyphs.toSet(), hasLength(glyphs.length), reason: 'all distinct');
    expect(index.pageCount, 3);
    expect(index.layout.residentBytesFor(glyphs.length), 48 * _mebibyte);
    // The 64 MiB ceiling of the static pool holds at the default glyph size.
    expect(
      index.layout.residentBytesFor(glyphs.length),
      lessThanOrEqualTo(64 * _mebibyte),
    );
  });

  test('the ceiling is 2704 glyphs: one more takes a fifth page', () {
    // Four pages of 676 cells are exactly 64 MiB at the 72 px glyph size; a
    // catalogue pack larger than this must raise windowed residency, not the
    // ceiling.
    final atCeiling = GlyphAtlasIndex(sampleGlyphCatalogue(count: 2704));
    final over = GlyphAtlasIndex(sampleGlyphCatalogue(count: 2705));

    expect(atCeiling.pageCount, 4);
    expect(
      atCeiling.layout.residentBytesFor(2704),
      lessThanOrEqualTo(64 * _mebibyte),
    );
    expect(over.pageCount, 5);
    expect(over.layout.residentBytesFor(2705), greaterThan(64 * _mebibyte));
  });
}
