import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the current catalogue bakes into three pages and 48 MiB', () {
    // Spec figures (baked emoji atlas): about 676 cells per page, three pages
    // for the current catalogue, about 48 MiB (64 MiB with mip levels).
    final glyphs = <String>{
      for (final category in emojiCatalogForLocale(const Locale('en')))
        for (final entry in category.entries) entry.glyph,
    }.toList();
    final index = GlyphAtlasIndex(glyphs);

    expect(index.pageCount, 3);
    expect(index.layout.residentBytesFor(glyphs.length), 48 * 1024 * 1024);
    // The 64 MiB ceiling of the static pool holds at the default glyph size.
    expect(
      index.layout.residentBytesFor(glyphs.length),
      lessThanOrEqualTo(64 * 1024 * 1024),
    );
  });
}
