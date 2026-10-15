import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  group('equality', () {
    test('keys of one variant are equal by value and hash alike', () {
      const a = ContentKey.unicode('\u{1F44D}');
      final b = ContentKey.unicode(String.fromCharCode(0x1F44D));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(const ContentKey.document('42'), const ContentKey.document('42'));
      expect(const ContentKey.external('u'), const ContentKey.external('u'));
    });

    test('different payloads are different keys', () {
      expect(
        const ContentKey.unicode('a'),
        isNot(const ContentKey.unicode('b')),
      );
      expect(
        const ContentKey.document('1'),
        isNot(const ContentKey.document('2')),
      );
    });

    test('the same payload under different variants is not the same key', () {
      const unicode = ContentKey.unicode('1');
      const document = ContentKey.document('1');
      const external = ContentKey.external('1');

      expect(unicode, isNot(document));
      expect(document, isNot(external));
      expect(unicode, isNot(external));
    });

    test('a sequence with and without FE0F are two keys, never folded', () {
      const plain = ContentKey.unicode('☂');
      const qualified = ContentKey.unicode('☂️');

      expect(plain, isNot(qualified));
      expect({plain, qualified}, hasLength(2));
    });

    test('keys work as map keys and set members', () {
      final byKey = <ContentKey, String>{
        const ContentKey.document('7'): 'doc',
        const ContentKey.unicode('x'): 'glyph',
      };

      expect(byKey[const ContentKey.document('7')], 'doc');
      expect(byKey[const ContentKey.unicode('x')], 'glyph');
      expect(byKey[const ContentKey.external('7')], isNull);
    });
  });

  group('construction', () {
    test('rejects an empty payload', () {
      final empty = StringBuffer().toString();

      expect(() => ContentKey.unicode(empty), throwsA(isA<AssertionError>()));
      expect(() => ContentKey.document(empty), throwsA(isA<AssertionError>()));
      expect(() => ContentKey.external(empty), throwsA(isA<AssertionError>()));
    });

    test('exposes the payload of each variant for pattern matching', () {
      String describe(ContentKey key) => switch (key) {
        ContentKey$Unicode(:final sequence) => 'u:$sequence',
        ContentKey$Document(:final id) => 'd:$id',
        ContentKey$External(:final id) => 'x:$id',
      };

      expect(describe(const ContentKey.unicode('a')), 'u:a');
      expect(describe(const ContentKey.document('1')), 'd:1');
      expect(describe(const ContentKey.external('2')), 'x:2');
    });
  });

  group('stable string encoding', () {
    test('writes unicode sequences as upper-case code point hex', () {
      expect(const ContentKey.unicode('\u{1F44D}').encoded, 'unicode:1F44D');
      expect(
        const ContentKey.unicode('\u{1F44D}\u{1F3FB}').encoded,
        'unicode:1F44D-1F3FB',
      );
      expect(const ContentKey.unicode('#').encoded, 'unicode:0023');
    });

    test('writes document and external ids verbatim', () {
      expect(const ContentKey.document('5368').encoded, 'document:5368');
      expect(const ContentKey.external('a:b c').encoded, 'external:a:b c');
    });

    test('round-trips every variant, including ZWJ, FE0F and keycap forms', () {
      const keys = <ContentKey>[
        ContentKey.unicode('\u{1F44D}'),
        ContentKey.unicode('☝️'),
        ContentKey.unicode('\u{1F3C3}‍♂️'),
        ContentKey.unicode('\u{1FAF1}\u{1F3FB}‍\u{1FAF2}\u{1F3FC}'),
        ContentKey.unicode('#️⃣'),
        ContentKey.unicode('\u{1F1E9}\u{1F1EA}'),
        ContentKey.document('9223372036854775807'),
        ContentKey.document('with:colon'),
        ContentKey.external('https://host/path?q=1'),
      ];

      for (final key in keys) {
        expect(ContentKey.parse(key.encoded), key, reason: key.encoded);
      }
    });

    test('round-trips a lone surrogate instead of corrupting the key', () {
      final key = ContentKey.unicode(String.fromCharCode(0xD83D));

      expect(ContentKey.parse(key.encoded), key);
    });

    test('accepts lower-case hex and re-encodes it canonically', () {
      final key = ContentKey.parse('unicode:1f44d-1f3fb');

      expect(key, const ContentKey.unicode('\u{1F44D}\u{1F3FB}'));
      expect(key.encoded, 'unicode:1F44D-1F3FB');
    });

    test('splits on the first colon only', () {
      expect(
        ContentKey.parse('document:a:b'),
        const ContentKey.document('a:b'),
      );
    });

    test('tryParse returns null for anything that is not an encoded key', () {
      const malformed = <String?>[
        null,
        '',
        'unicode',
        'unicode:',
        'unicode:ZZ',
        'unicode:1F44D-',
        'unicode:-1F44D',
        'unicode:1F44D--1F3FB',
        'unicode:110000',
        'unicode:1234567',
        'unicode:+1F44D',
        'document:',
        'external:',
        'sticker:1',
        'Unicode:1F44D',
        '1F44D',
      ];

      for (final source in malformed) {
        expect(ContentKey.tryParse(source), isNull, reason: '$source');
      }
    });

    test('parse throws a FormatException naming the input', () {
      expect(
        () => ContentKey.parse('sticker:1'),
        throwsA(
          isA<FormatException>().having((e) => e.source, 'source', 'sticker:1'),
        ),
      );
    });
  });

  group('toString', () {
    test('names the variant and prints unicode as hex, not as a glyph', () {
      expect(
        const ContentKey.unicode('\u{1F44D}').toString(),
        'ContentKey.unicode(1F44D)',
      );
      expect(
        const ContentKey.document('42').toString(),
        'ContentKey.document(42)',
      );
      expect(
        const ContentKey.external('u').toString(),
        'ContentKey.external(u)',
      );
    });
  });
}
