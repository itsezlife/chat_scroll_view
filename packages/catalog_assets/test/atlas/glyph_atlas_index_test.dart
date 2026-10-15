import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _glyphs(int count) => [for (var i = 0; i < count; i++) 'g$i'];

void main() {
  group('GlyphAtlasLayout', () {
    test('default layout is the capped 72 px glyph on a 2048 px page', () {
      const layout = GlyphAtlasLayout();

      expect(layout.glyphSize, 72);
      expect(layout.cellSize, 76); // 72 + a 2 px transparent gutter per side
      expect(layout.cellsPerPage, 676); // 26 x 26
    });

    test('a smaller wanted cell bakes smaller, a larger one is capped', () {
      // 34.84 logical px at the reference density is a 98 px glyph: capped.
      expect(
        GlyphAtlasLayout.forCell(
          logicalExtent: 34.84,
          devicePixelRatio: 2.8125,
        ).glyphSize,
        GlyphAtlasLayout.maxGlyphSize,
      );
      // 20 logical px at 2x is 40 physical px: below the cap, kept exact.
      expect(
        GlyphAtlasLayout.forCell(
          logicalExtent: 20,
          devicePixelRatio: 2,
        ).glyphSize,
        40,
      );
    });

    test('a glyph size over the cap is rejected', () {
      expect(
        () => GlyphAtlasLayout(glyphSize: GlyphAtlasLayout.maxGlyphSize + 1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('glyph rectangles tile the page without overlap or overflow', () {
      const layout = GlyphAtlasLayout();
      final rects = [
        for (var s = 0; s < layout.cellsPerPage; s++) layout.glyphRect(s),
      ];
      const page = Rect.fromLTWH(
        0,
        0,
        GlyphAtlasLayout.pageSize * 1.0,
        GlyphAtlasLayout.pageSize * 1.0,
      );

      expect(rects.first, const Rect.fromLTWH(2, 2, 72, 72));
      expect(rects[1], const Rect.fromLTWH(78, 2, 72, 72));
      expect(rects[26], const Rect.fromLTWH(2, 78, 72, 72));
      for (final r in rects) {
        expect(
          page.contains(r.topLeft) && page.contains(r.bottomRight),
          isTrue,
        );
      }
      // Two glyph rects are at least a gutter pair apart: 4 px.
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].overlaps(rects[i - 1].inflate(1.9)), isFalse);
      }
    });
  });

  group('GlyphAtlasIndex', () {
    const layout = GlyphAtlasLayout();

    test('a catalogue that fits exactly one page needs one page', () {
      final index = GlyphAtlasIndex(_glyphs(layout.cellsPerPage));

      expect(index.pageCount, 1);
    });

    test('one glyph more than a page needs a second page', () {
      final index = GlyphAtlasIndex(_glyphs(layout.cellsPerPage + 1));

      expect(index.pageCount, 2);
      expect(index.placementOf('g${layout.cellsPerPage}')!.pageIndex, 1);
    });

    test('an empty catalogue needs no pages', () {
      expect(GlyphAtlasIndex(const []).pageCount, 0);
    });

    test('every glyph maps to its own page and rectangle', () {
      final glyphs = _glyphs(layout.cellsPerPage * 2 + 5);
      final index = GlyphAtlasIndex(glyphs);

      final seen = <(int, Rect)>{};
      for (final glyph in glyphs) {
        final sprite = index.placementOf(glyph)!;
        expect(
          seen.add((sprite.pageIndex, sprite.source)),
          isTrue,
          reason: '$glyph shares a cell',
        );
        expect(sprite.source.width, layout.glyphSize);
      }
      expect(
        index.placementOf('g0'),
        GlyphSprite(pageIndex: 0, source: layout.glyphRect(0)),
      );
      expect(
        index.placementOf('g${layout.cellsPerPage + 2}'),
        GlyphSprite(pageIndex: 1, source: layout.glyphRect(2)),
      );
    });

    test('an unknown glyph has no placement', () {
      expect(GlyphAtlasIndex(_glyphs(3)).placementOf('absent'), isNull);
    });

    test('a repeated glyph occupies one cell', () {
      final index = GlyphAtlasIndex(['a', 'b', 'a', 'c']);

      expect(index.glyphCount, 3);
      expect(index.placementOf('c')!.source, layout.glyphRect(2));
    });

    test('glyphsOnPage lists the glyphs of one page in cell order', () {
      final index = GlyphAtlasIndex(_glyphs(layout.cellsPerPage + 2));

      expect(index.glyphsOnPage(1), [
        'g${layout.cellsPerPage}',
        'g${layout.cellsPerPage + 1}',
      ]);
      expect(index.glyphsOnPage(0), hasLength(layout.cellsPerPage));
    });
  });

  group('current catalogue budget', () {
    // Spec figures: three pages, 48 MiB raw. The count comes from the real
    // catalogue in `current_catalogue_test.dart`; here the arithmetic only.
    test('three pages are 48 MiB raw', () {
      const layout = GlyphAtlasLayout();

      expect(layout.pageBytes, 16 * 1024 * 1024);
      expect(
        layout.residentBytesFor(layout.cellsPerPage * 2 + 1),
        48 * 1024 * 1024,
      );
    });
  });
}
