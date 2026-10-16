import 'dart:math';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

Entity bold(int offset, int length) => Entity(offset, length, EntityKind.bold);

Entity italic(int offset, int length) =>
    Entity(offset, length, EntityKind.italic);

void main() {
  group('insert', () {
    test('inside an entity grows it', () {
      final text = RichText('abcd', [bold(1, 2)]);

      final result = text.insert(2, const RichText.plain('XY'));

      expect(result.plain, 'abXYcd');
      expect(result.entities, [bold(1, 4)]);
    });

    test('at the edges of an entity does not extend it', () {
      final text = RichText('abcd', [bold(1, 2)]);

      expect(
        text.insert(1, const RichText.plain('X')).entities,
        [bold(2, 2)],
        reason: 'before the entity: it shifts right',
      );
      expect(
        text.insert(3, const RichText.plain('X')).entities,
        [bold(1, 2)],
        reason: 'after the entity: it stays',
      );
    });

    test('inserted text carries its own entities', () {
      final text = RichText('abcd', [bold(0, 1)]);

      final result = text.insert(2, RichText('XY', [italic(0, 2)]));

      expect(result.plain, 'abXYcd');
      expect(result.entities, [bold(0, 1), italic(2, 2)]);
    });

    test('inserting bold next to bold continues the run', () {
      final text = RichText('abcd', [bold(0, 2)]);

      final result = text.insert(2, RichText('XY', [bold(0, 2)]));

      expect(result.entities, [bold(0, 4)]);
    });

    test('inside an atomic entity removes it', () {
      final text = RichText('a@bob c', const [
        Entity(1, 4, EntityKind.mention('bob')),
      ]);

      final result = text.insert(3, const RichText.plain('X'));

      expect(result.plain, 'a@bXob c');
      expect(result.entities, isEmpty);
    });

    test('next to an atomic entity keeps it', () {
      final text = RichText('a@bob c', const [
        Entity(1, 4, EntityKind.mention('bob')),
      ]);

      expect(text.insert(5, const RichText.plain('X')).entities, [
        const Entity(1, 4, EntityKind.mention('bob')),
      ]);
      expect(text.insert(1, const RichText.plain('X')).entities, [
        const Entity(2, 4, EntityKind.mention('bob')),
      ]);
    });

    test('rejects an offset outside the text or inside a surrogate pair', () {
      const text = RichText.plain('a\u{1F44D}b');

      expect(() => text.insert(5, RichText.empty), throwsRangeError);
      expect(() => text.insert(-1, RichText.empty), throwsRangeError);
      expect(() => text.insert(2, RichText.empty), throwsArgumentError);
    });
  });

  group('delete', () {
    test('across an entity edge shortens it', () {
      final text = RichText('abcdef', [bold(2, 3)]);

      expect(text.delete(0, 3).entities, [bold(0, 2)]);
      expect(text.delete(4, 6).entities, [bold(2, 2)]);
    });

    test('inside an entity shrinks it', () {
      final text = RichText('abcdef', [bold(1, 4)]);

      final result = text.delete(2, 4);

      expect(result.plain, 'abef');
      expect(result.entities, [bold(1, 2)]);
    });

    test('over a whole entity removes it', () {
      final text = RichText('abcdef', [bold(2, 2), italic(0, 1)]);

      final result = text.delete(1, 5);

      expect(result.plain, 'af');
      expect(result.entities, [italic(0, 1)]);
    });

    test('across several entities keeps what is left of each', () {
      final text = RichText('abcdefgh', [bold(0, 4), italic(3, 4)]);

      final result = text.delete(2, 5);

      expect(result.plain, 'abfgh');
      expect(result.entities, [bold(0, 2), italic(2, 2)]);
    });

    test('across a mention removes it, even when only part of it goes', () {
      final text = RichText('a@bob c', [
        const Entity(1, 4, EntityKind.mention('bob')),
        bold(0, 7),
      ]);

      final result = text.delete(3, 6);

      expect(result.plain, 'a@bc');
      expect(result.entities, [bold(0, 4)]);
    });

    test(
      'after a deletion a text style gives up the whitespace it exposes',
      () {
        final text = RichText('ab cd', [bold(0, 5)]);

        expect(text.delete(3, 5).entities, [bold(0, 2)]);
      },
    );

    test('an empty range changes nothing', () {
      final text = RichText('abc', [bold(0, 2)]);

      expect(text.delete(1, 1), text);
    });

    test('rejects a range inside a surrogate pair', () {
      const text = RichText.plain('a\u{1F44D}b');

      expect(() => text.delete(0, 2), throwsArgumentError);
      expect(text.delete(1, 3).plain, 'ab');
    });
  });

  group('replaceRange', () {
    test('over an entity boundary keeps the part outside the range', () {
      final text = RichText('abcdef', [bold(1, 3)]);

      final result = text.replaceRange(3, 5, const RichText.plain('XYZ'));

      expect(result.plain, 'abcXYZf');
      expect(result.entities, [bold(1, 2)]);
    });

    test('over the start of an entity moves it behind the replacement', () {
      final text = RichText('abcdef', [bold(2, 3)]);

      final result = text.replaceRange(0, 3, const RichText.plain('X'));

      expect(result.plain, 'Xdef');
      expect(result.entities, [bold(1, 2)]);
    });

    test('inside an entity keeps it around the replacement', () {
      final text = RichText('abcdef', [bold(0, 6)]);

      final result = text.replaceRange(2, 4, const RichText.plain('WXYZ'));

      expect(result.plain, 'abWXYZef');
      expect(result.entities, [bold(0, 8)]);
    });

    test('exactly over an entity drops it, then takes the replacement\'s', () {
      final text = RichText('abcdef', [bold(2, 2)]);

      final result = text.replaceRange(2, 4, RichText('XY', [italic(0, 2)]));

      expect(result.plain, 'abXYef');
      expect(result.entities, [italic(2, 2)]);
    });

    test('with an invalid combination throws instead of guessing', () {
      final text = RichText('abcdef', const [Entity(0, 6, EntityKind.code)]);

      expect(
        () => text.replaceRange(2, 4, RichText('XY', [bold(0, 2)])),
        throwsArgumentError,
      );
    });

    test('keeps a quote on whole lines', () {
      final text = RichText('ab\ncd', const [Entity(0, 2, EntityKind.quote)]);

      final result = text.replaceRange(2, 2, const RichText.plain('X'));

      expect(result.plain, 'abX\ncd');
      expect(result.entities, [const Entity(0, 3, EntityKind.quote)]);
    });

    test('works with emoji and ZWJ sequences by code unit', () {
      const family = '\u{1F468}‍\u{1F469}';
      final text = RichText('a${family}b', [bold(1, 5)]);

      final result = text.replaceRange(6, 7, const RichText.plain('cc'));

      expect(result.plain, 'a${family}cc');
      expect(result.entities, [bold(1, 5)]);
    });
  });

  group('slice', () {
    test('clips entities to the range', () {
      final text = RichText('abcdef', [bold(0, 4), italic(3, 3)]);

      final slice = text.slice(2, 5);

      expect(slice.plain, 'cde');
      expect(slice.entities, [bold(0, 2), italic(1, 2)]);
    });

    test('keeps an atomic entity only when it fits whole', () {
      final text = RichText('a@bob c', const [
        Entity(1, 4, EntityKind.mention('bob')),
      ]);

      expect(text.slice(1, 5).entities, hasLength(1));
      expect(text.slice(2, 7).entities, isEmpty);
    });

    test('a slice of the whole text is the text', () {
      final text = RichText('abc', [bold(0, 2)]);

      expect(text.slice(0, 3), text);
    });
  });

  group('any edit with plain text', () {
    const alphabet = ['a', 'b', ' ', '\n', 'x', '\u{1F44D}', '@'];

    RichText? generate(Random random) {
      final plain = StringBuffer();
      for (var i = random.nextInt(14); i > 0; i--) {
        plain.write(alphabet[random.nextInt(alphabet.length)]);
      }
      final source = plain.toString();
      final entities = <Entity>[];
      for (var i = random.nextInt(6); i > 0 && source.isNotEmpty; i--) {
        final offset = random.nextInt(source.length);
        final span = 1 + random.nextInt(source.length - offset);
        final kind = switch (random.nextInt(10)) {
          0 => EntityKind.bold,
          1 => EntityKind.italic,
          2 => EntityKind.underline,
          3 => EntityKind.strike,
          4 => EntityKind.code,
          5 => EntityKind.quote,
          6 => const EntityKind.link('u'),
          7 => const EntityKind.mention('m'),
          8 => const EntityKind.inlineContent(ContentKey.document('1')),
          _ => EntityKind.bold,
        };
        entities.add(Entity(offset, span, kind));
      }
      try {
        return RichText(source, entities);
        // The generator is blind to the entity rules; a draw that breaks them
        // is skipped, not a failure.
        // ignore: avoid_catching_errors
      } on ArgumentError {
        return null;
      }
    }

    test('yields a canonical text with the edited plain text', () {
      final random = Random(31);
      var edits = 0;
      for (var i = 0; i < 20000; i++) {
        final text = generate(random);
        if (text == null) continue;
        var start = random.nextInt(text.length + 1);
        var end = start + random.nextInt(text.length - start + 1);
        // A range cannot cut a surrogate pair; step outwards to a boundary.
        if (start > 0 &&
            start < text.length &&
            text.plain.codeUnitAt(start) >> 10 == 0x37) {
          start--;
        }
        if (end > 0 &&
            end < text.length &&
            text.plain.codeUnitAt(end) >> 10 == 0x37) {
          end++;
        }
        final inserted = alphabet[random.nextInt(alphabet.length)];

        final result = text.replaceRange(start, end, RichText.plain(inserted));

        edits++;
        expect(result.plain, text.plain.replaceRange(start, end, inserted));
        expect(RichText(result.plain, result.entities), result);
      }

      expect(edits, greaterThan(3000));
    });
  });
}
