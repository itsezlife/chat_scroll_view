import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

Entity bold(int offset, int length) => Entity(offset, length, EntityKind.bold);

void main() {
  group('construction', () {
    test('plain text carries no entities', () {
      const text = RichText.plain('hello');

      expect(text.plain, 'hello');
      expect(text.entities, isEmpty);
      expect(text.length, 5);
      expect(text.isEmpty, isFalse);
      expect(RichText.empty.isEmpty, isTrue);
    });

    test('the entity list is an unmodifiable copy', () {
      final source = [bold(0, 2)];
      final text = RichText('hello', source);
      source.add(bold(3, 2));

      expect(text.entities, [bold(0, 2)]);
      expect(() => text.entities.add(bold(3, 2)), throwsUnsupportedError);
    });

    test('is a value of its text and entities', () {
      final a = RichText('hello', [bold(0, 2)]);
      final b = RichText('hello', [bold(0, 2)]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(RichText('hello', [bold(0, 3)])));
      expect(a, isNot(RichText('hellO', [bold(0, 2)])));
      expect(a, isNot(const RichText.plain('hello')));
    });

    test(
      'entities are sorted by offset, then longer first, on construction',
      () {
        final text = RichText('abcdef', const [
          Entity(3, 2, EntityKind.italic),
          Entity(0, 2, EntityKind.bold),
          Entity(0, 5, EntityKind.strike),
        ]);

        expect(text.entities, [
          const Entity(0, 5, EntityKind.strike),
          const Entity(0, 2, EntityKind.bold),
          const Entity(3, 2, EntityKind.italic),
        ]);
      },
    );

    test('the same entities in any order give an equal value', () {
      final a = RichText('abcdef', [
        bold(0, 2),
        const Entity(1, 3, EntityKind.italic),
      ]);
      final b = RichText('abcdef', [
        const Entity(1, 3, EntityKind.italic),
        bold(0, 2),
      ]);

      expect(a, b);
    });
  });

  group('validation', () {
    test('rejects an entity that runs past the end of the text', () {
      expect(() => RichText('abc', [bold(1, 3)]), throwsArgumentError);
      expect(() => RichText('abc', [bold(4, 1)]), throwsArgumentError);
    });

    test('accepts an entity that ends exactly at the end of the text', () {
      expect(RichText('abc', [bold(1, 2)]).entities, [bold(1, 2)]);
    });

    test('rejects an entity that splits a surrogate pair', () {
      const thumbsUp = '\u{1F44D}';
      expect(
        () => RichText('a$thumbsUp', [bold(0, 2)]),
        throwsArgumentError,
        reason: 'ends between the two halves',
      );
      expect(
        () => RichText('a${thumbsUp}b', [bold(2, 2)]),
        throwsArgumentError,
        reason: 'starts between the two halves',
      );
      expect(RichText('a${thumbsUp}b', [bold(1, 2)]).entities, hasLength(1));
    });

    test('does not treat a ZWJ sequence as one unit', () {
      const family = '\u{1F468}‍\u{1F469}';
      // Cutting after the first code point is legal: only surrogate pairs are
      // protected, grapheme clusters are the host's business.
      expect(RichText(family, [bold(0, 2)]).entities, [bold(0, 2)]);
    });

    test('rejects a link without a url or with a line break in it', () {
      expect(
        () => RichText('abc', const [Entity(0, 3, EntityKind.link(''))]),
        throwsArgumentError,
      );
      expect(
        () => RichText('abc', const [Entity(0, 3, EntityKind.link('a\nb'))]),
        throwsArgumentError,
      );
    });

    test('reserves the mention scheme for mentions', () {
      expect(
        () =>
            RichText('abc', const [Entity(0, 3, EntityKind.link('mention:x'))]),
        throwsArgumentError,
      );
    });

    test('rejects a mention without an id', () {
      expect(
        () => RichText('abc', const [Entity(0, 3, EntityKind.mention(''))]),
        throwsArgumentError,
      );
    });

    test('rejects an atomic entity that spans a line break', () {
      expect(
        () => RichText('a\nb', const [Entity(0, 3, EntityKind.mention('x'))]),
        throwsArgumentError,
      );
    });
  });

  group('normalisation', () {
    test('takes time linear in the size of a long text with many entities', () {
      const word = 'word ';
      final plain = word * 50000;
      final entities = [
        for (var i = 0; i < 50000; i++)
          Entity(
            i * word.length,
            i.isEven ? 5 : 4,
            i.isEven ? EntityKind.bold : EntityKind.code,
          ),
      ];
      final timer = Stopwatch()..start();

      final text = RichText(plain, entities);

      timer.stop();
      // Each bold word gives up the space after it.
      expect(text.entities, hasLength(50000));
      expect(text.entities.first, const Entity(0, 4, EntityKind.bold));
      expect(timer.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('merges touching and overlapping runs of the same style', () {
      expect(
        RichText('abcdef', [bold(0, 2), bold(2, 2), bold(3, 3)]).entities,
        [bold(0, 6)],
      );
    });

    test('drops an exact duplicate', () {
      expect(RichText('abc', [bold(0, 2), bold(0, 2)]).entities, [bold(0, 2)]);
    });

    test('keeps different styles that overlap partially', () {
      final text = RichText('abcdef', [
        bold(0, 4),
        const Entity(2, 4, EntityKind.italic),
      ]);

      expect(text.entities, hasLength(2));
    });

    test('keeps runs of different links apart', () {
      final text = RichText('abcd', const [
        Entity(0, 2, EntityKind.link('https://a')),
        Entity(2, 2, EntityKind.link('https://b')),
      ]);

      expect(text.entities, hasLength(2));
    });

    test('merges touching links to the same target', () {
      final text = RichText('abcd', const [
        Entity(0, 2, EntityKind.link('https://a')),
        Entity(2, 2, EntityKind.link('https://a')),
      ]);

      expect(text.entities, [const Entity(0, 4, EntityKind.link('https://a'))]);
    });

    test('does not merge two mentions of the same id', () {
      final text = RichText('@a@a', const [
        Entity(0, 2, EntityKind.mention('a')),
        Entity(2, 2, EntityKind.mention('a')),
      ]);

      expect(text.entities, hasLength(2));
    });

    test('splits a style at line breaks', () {
      expect(RichText('ab\ncd', [bold(0, 5)]).entities, [
        bold(0, 2),
        bold(3, 2),
      ]);
    });

    test('trims whitespace from the edges of a text style', () {
      expect(RichText('  ab  ', [bold(0, 6)]).entities, [bold(2, 2)]);
      expect(
        RichText('a b', [bold(1, 1)]).entities,
        isEmpty,
        reason: 'a style over whitespace only has nothing to style',
      );
    });

    test('keeps whitespace inside code and links', () {
      expect(RichText(' a ', const [Entity(0, 3, EntityKind.code)]).entities, [
        const Entity(0, 3, EntityKind.code),
      ]);
      expect(
        RichText(' a ', const [Entity(0, 3, EntityKind.link('x'))]).entities,
        [const Entity(0, 3, EntityKind.link('x'))],
      );
    });

    test('widens a quote to whole lines', () {
      expect(
        RichText('ab\ncd\nef', const [Entity(4, 1, EntityKind.quote)]).entities,
        [const Entity(3, 2, EntityKind.quote)],
      );
      expect(
        RichText('ab\ncd\nef', const [Entity(1, 3, EntityKind.quote)]).entities,
        [const Entity(0, 5, EntityKind.quote)],
      );
    });

    test('is idempotent', () {
      final once = RichText('  ab\ncd ', [
        bold(0, 8),
        const Entity(1, 6, EntityKind.quote),
      ]);

      expect(RichText(once.plain, once.entities), once);
    });
  });

  group('exclusivity', () {
    test('code can sit inside another style but not hold one', () {
      expect(
        RichText('abcdef', [
          bold(0, 6),
          const Entity(2, 2, EntityKind.code),
        ]).entities,
        hasLength(2),
      );
      expect(
        () => RichText('abcdef', const [
          Entity(0, 6, EntityKind.code),
          Entity(2, 2, EntityKind.italic),
        ]),
        throwsArgumentError,
      );
      expect(
        () => RichText('abcdef', const [
          Entity(0, 4, EntityKind.code),
          Entity(2, 4, EntityKind.italic),
        ]),
        throwsArgumentError,
      );
    });

    test('a mention or inline content is whole inside or outside others', () {
      const key = ContentKey.unicode('\u{1F44D}');
      expect(
        () => RichText('a\u{1F44D}b', [
          const Entity(1, 2, EntityKind.inlineContent(key)),
          bold(0, 2),
        ]),
        throwsArgumentError,
      );
      expect(
        RichText('a\u{1F44D}b', [
          const Entity(1, 2, EntityKind.inlineContent(key)),
          bold(0, 3),
        ]).entities,
        hasLength(2),
      );
    });

    test('a link and code never overlap', () {
      expect(
        () => RichText('abcd', const [
          Entity(0, 4, EntityKind.link('u')),
          Entity(1, 2, EntityKind.code),
        ]),
        throwsArgumentError,
      );
    });

    test('code holds no mention or inline content', () {
      expect(
        () => RichText('@ab', const [
          Entity(0, 3, EntityKind.code),
          Entity(0, 3, EntityKind.mention('a')),
        ]),
        throwsArgumentError,
      );
    });

    test('trimming a style leaves whitespace that sits inside code', () {
      final text = RichText('a  b', const [
        Entity(0, 4, EntityKind.bold),
        Entity(1, 2, EntityKind.code),
      ]);

      expect(text.entities, [
        const Entity(0, 4, EntityKind.bold),
        const Entity(1, 2, EntityKind.code),
      ]);
    });

    test('two atomic entities never overlap', () {
      expect(
        () => RichText('@ab', const [
          Entity(0, 3, EntityKind.mention('a')),
          Entity(0, 3, EntityKind.mention('b')),
        ]),
        throwsArgumentError,
      );
    });

    test('links do not overlap each other or hold a mention', () {
      expect(
        () => RichText('abcd', const [
          Entity(0, 3, EntityKind.link('a')),
          Entity(2, 2, EntityKind.link('b')),
        ]),
        throwsArgumentError,
      );
      expect(
        () => RichText('@abcd', const [
          Entity(0, 5, EntityKind.link('a')),
          Entity(0, 2, EntityKind.mention('a')),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('reading entities', () {
    test('reads the text an entity covers', () {
      final text = RichText('hello world', [bold(6, 5)]);

      expect(text.textOf(text.entities.single), 'world');
    });

    test(
      'reads an inline content reference with its plain-text alternative',
      () {
        const key = ContentKey.document('5368');
        final text = RichText('a:)b', [
          const Entity(1, 2, EntityKind.inlineContent(key)),
          bold(0, 4),
        ]);

        final ref = text.inlineContentOf(
          text.entities.firstWhere((e) => e.kind is EntityKind$InlineContent),
        );

        expect(ref, const InlineContentRef(key: key, alternativeText: ':)'));
        expect(text.inlineContentOf(bold(0, 4)), isNull);
      },
    );
  });
}
