import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = GlyphCacheKey(
    artVersion: 'art-1',
    devicePixelRatio: 2.75,
    glyphSize: 72,
    layoutVersion: 1,
    catalogueHash: 'abc',
  );

  group('GlyphCacheKey.verdictAgainst', () {
    test('an identical key is a hit', () {
      expect(base.verdictAgainst(base), GlyphCacheVerdict.hit);
    });

    test('a changed art version keeps the old pages as stale', () {
      final stored = base.copyWith(artVersion: 'art-0');
      expect(base.verdictAgainst(stored), GlyphCacheVerdict.stale);
    });

    test('a changed catalogue keeps the old pages as stale', () {
      final stored = base.copyWith(catalogueHash: 'zzz');
      expect(base.verdictAgainst(stored), GlyphCacheVerdict.stale);
    });

    test('a changed density discards the old pages', () {
      final stored = base.copyWith(devicePixelRatio: 3);
      expect(base.verdictAgainst(stored), GlyphCacheVerdict.discard);
    });

    test('a changed baked glyph size discards the old pages', () {
      final stored = base.copyWith(glyphSize: 64);
      expect(base.verdictAgainst(stored), GlyphCacheVerdict.discard);
    });

    test('a changed layout version discards the old pages', () {
      final stored = base.copyWith(layoutVersion: 0);
      expect(base.verdictAgainst(stored), GlyphCacheVerdict.discard);
    });

    test('a discard component wins over a stale one', () {
      final stored = base.copyWith(artVersion: 'art-0', devicePixelRatio: 3);
      expect(base.verdictAgainst(stored), GlyphCacheVerdict.discard);
    });
  });

  group('GlyphCacheRecord', () {
    test('survives a round trip through json, glyphs included', () {
      const record = GlyphCacheRecord(
        key: base,
        glyphs: ['😀', '👨‍👩‍👧‍👦', '🇯🇵', r'a"b\c'],
      );
      final back = GlyphCacheRecord.fromJson(record.toJson());
      expect(back.key, base);
      expect(back.glyphs, record.glyphs);
    });

    test('rejects text that is not a record', () {
      expect(
        () => GlyphCacheRecord.fromJson('{"nope":1}'),
        throwsFormatException,
      );
      expect(
        () => GlyphCacheRecord.fromJson('not json'),
        throwsFormatException,
      );
      expect(() => GlyphCacheRecord.fromJson(''), throwsFormatException);
    });

    test('rejects a record written by another format version', () {
      final json = const GlyphCacheRecord(key: base, glyphs: ['a']).toJson();
      expect(
        () => GlyphCacheRecord.fromJson(
          json.replaceFirst('"format":1', '"format":99'),
        ),
        throwsFormatException,
      );
    });
  });

  group('GlyphCacheKey.catalogueHashOf', () {
    test('is stable for the same glyphs and differs when one changes', () {
      final a = GlyphCacheKey.catalogueHashOf(['a', 'b', '😀']);
      expect(GlyphCacheKey.catalogueHashOf(['a', 'b', '😀']), a);
      expect(GlyphCacheKey.catalogueHashOf(['a', 'b', '😁']), isNot(a));
    });

    test('depends on the order, because order decides where a glyph sits', () {
      expect(
        GlyphCacheKey.catalogueHashOf(['a', 'b']),
        isNot(GlyphCacheKey.catalogueHashOf(['b', 'a'])),
      );
    });

    test('does not confuse a split glyph list with a joined one', () {
      expect(
        GlyphCacheKey.catalogueHashOf(['ab', 'c']),
        isNot(GlyphCacheKey.catalogueHashOf(['a', 'bc'])),
      );
    });
  });
}
