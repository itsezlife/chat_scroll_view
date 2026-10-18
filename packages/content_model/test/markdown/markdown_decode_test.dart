import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

const _bold = EntityKind.bold;
const _italic = EntityKind.italic;

RichText decode(String markdown) => RichTextMarkdown.decode(markdown);

void main() {
  group('plain text', () {
    test('without markup is plain text', () {
      expect(decode('hello, world'), const RichText.plain('hello, world'));
      expect(decode(''), RichText.empty);
    });

    test('keeps line breaks and blank lines', () {
      expect(decode('a\n\nb\n'), const RichText.plain('a\n\nb\n'));
    });

    test('reads a backslash before punctuation as the punctuation', () {
      expect(decode(r'a\*b\_c\\d\#'), const RichText.plain(r'a*b_c\d#'));
    });

    test('keeps a backslash before anything else', () {
      expect(decode(r'a\b \'), const RichText.plain(r'a\b \'));
    });

    test('keeps emoji, ZWJ sequences and FE0F as written', () {
      const text = '\u{1F468}‍\u{1F469} ☂️';

      expect(decode(text), const RichText.plain(text));
    });
  });

  group('styles', () {
    test('reads each style', () {
      expect(decode('**x**').entities, [const Entity(0, 1, _bold)]);
      expect(decode('*x*').entities, [const Entity(0, 1, _italic)]);
      expect(decode('_x_').entities, [const Entity(0, 1, _italic)]);
      expect(decode('__x__').entities, [
        const Entity(0, 1, EntityKind.underline),
      ]);
      expect(decode('~~x~~').entities, [const Entity(0, 1, EntityKind.strike)]);
      expect(decode('||x||').entities, [
        const Entity(0, 1, EntityKind.spoiler),
      ]);
      expect(decode('`x`').entities, [const Entity(0, 1, EntityKind.code)]);
    });

    test('puts the entity on the text, not on the markers', () {
      final text = decode('a **bc** d');

      expect(text.plain, 'a bc d');
      expect(text.entities, [const Entity(2, 2, _bold)]);
    });

    test('reads nested and adjacent styles', () {
      expect(decode('***x***').entities, [
        const Entity(0, 1, _bold),
        const Entity(0, 1, _italic),
      ]);
      expect(decode('**a*b*c**').entities, [
        const Entity(0, 3, _bold),
        const Entity(1, 1, _italic),
      ]);
      expect(decode('**a***b*').entities, [
        const Entity(0, 1, _bold),
        const Entity(1, 1, _italic),
      ]);
      expect(decode('*a***b**').entities, [
        const Entity(0, 1, _italic),
        const Entity(1, 1, _bold),
      ]);
    });

    test('leaves unmatched and whitespace-flanked markers as text', () {
      expect(decode('**oops'), const RichText.plain('**oops'));
      expect(decode('5 * 6 * 7'), const RichText.plain('5 * 6 * 7'));
      expect(decode('** a **'), const RichText.plain('** a **'));
      expect(decode('a ~~ b ~~ c'), const RichText.plain('a ~~ b ~~ c'));
      expect(decode('~x~ |y|'), const RichText.plain('~x~ |y|'));
    });

    test('leaves an underscore inside a word alone', () {
      expect(
        decode('snake_case_name'),
        const RichText.plain('snake_case_name'),
      );
    });

    test('does not read markers inside code', () {
      final text = decode('`a **b** _c_`');

      expect(text.plain, 'a **b** _c_');
      expect(text.entities, [const Entity(0, 11, EntityKind.code)]);
    });

    test('reads code fences of any length and the padding rule', () {
      expect(decode('``a`b``').plain, 'a`b');
      expect(decode('`` `a ``').plain, '`a');
      expect(decode('`  a  `').plain, ' a ');
      expect(decode('`  `').plain, '  ');
      expect(decode('`unterminated'), const RichText.plain('`unterminated'));
    });

    test('does not let a style cross a line break', () {
      expect(decode('**a\nb**'), const RichText.plain('**a\nb**'));
    });
  });

  group('links, mentions and inline content', () {
    test('reads a link and its label', () {
      final text = decode('see [this](https://a.b/c) now');

      expect(text.plain, 'see this now');
      expect(text.entities, [
        const Entity(4, 4, EntityKind.link('https://a.b/c')),
      ]);
    });

    test('reads styles inside a link label', () {
      final text = decode('[a**b**c](u)');

      expect(text.plain, 'abc');
      expect(text.entities, [
        const Entity(0, 3, EntityKind.link('u')),
        const Entity(1, 1, _bold),
      ]);
    });

    test('reads escaped brackets and parentheses in label and target', () {
      final text = decode(r'[a\]b](https://x/a_\(b\))');

      expect(text.plain, 'a]b');
      expect(text.entities, [
        const Entity(0, 3, EntityKind.link('https://x/a_(b)')),
      ]);
    });

    test('reads a balanced parenthesis in a bare target', () {
      expect(decode('[t](https://x/a_(b))').entities, [
        const Entity(0, 1, EntityKind.link('https://x/a_(b)')),
      ]);
    });

    test('reads a target between angle brackets', () {
      expect(decode('[t](<https://x/a b>)').entities, [
        const Entity(0, 1, EntityKind.link('https://x/a b')),
      ]);
    });

    test('reads a mention by its scheme', () {
      final text = decode('hi [@alice](mention:alice)!');

      expect(text.plain, 'hi @alice!');
      expect(text.entities, [const Entity(3, 6, EntityKind.mention('alice'))]);
    });

    test('reads inline content by the encoded content key', () {
      final text = decode('a![\u{1F44D}](unicode:1F44D)b ![:)](document:5368)');

      expect(text.plain, 'a\u{1F44D}b :)');
      expect(text.entities, [
        const Entity(
          1,
          2,
          EntityKind.inlineContent(ContentKey.unicode('\u{1F44D}')),
        ),
        const Entity(
          5,
          2,
          EntityKind.inlineContent(ContentKey.document('5368')),
        ),
      ]);
    });

    test('keeps only the alt text of an image it cannot place', () {
      expect(
        decode('![logo](https://x/y.png) and ![x](unicode:ZZ)').plain,
        'logo and x',
      );
      expect(decode('![logo](https://x/y.png)').entities, isEmpty);
    });

    test('leaves broken link syntax as text', () {
      for (final broken in const [
        '[a](',
        '[a]',
        '[a] (u)',
        '[a]()',
        '[](u)',
        '[a](u',
        '[a',
      ]) {
        expect(decode(broken), RichText.plain(broken), reason: broken);
      }
    });

    test('does not nest a link inside a link label', () {
      final text = decode('[a [b](v) c](u)');

      expect(text.entities.whereType<Entity>().length, 1);
      expect(text.plain, 'a [b](v) c');
    });

    test('a bang before a bracket that is escaped is a bang', () {
      expect(decode(r'wow\![x](u)').plain, 'wow!x');
    });
  });

  group('quotes', () {
    test('reads consecutive quote lines as one quote', () {
      final text = decode('a\n> b\n> c');

      expect(text.plain, 'a\nb\nc');
      expect(text.entities, [const Entity(2, 3, EntityKind.quote)]);
    });

    test('a blank line ends the quote and is not part of the text', () {
      final text = decode('> q\n\nrest');

      expect(text.plain, 'q\nrest');
      expect(text.entities, [const Entity(0, 1, EntityKind.quote)]);
    });

    test('ends the quote at a line without the marker', () {
      final text = decode('> q\nrest');

      expect(text.plain, 'q\nrest');
      expect(text.entities, [const Entity(0, 1, EntityKind.quote)]);
    });

    test('reads a bare marker as an empty line and two quotes as two', () {
      expect(decode('> a\n>\n> b').plain, 'a\n\nb');
      expect(decode('> a\n\n> b').entities, [
        const Entity(0, 1, EntityKind.quote),
        const Entity(2, 1, EntityKind.quote),
      ]);
    });

    test('reads styles inside a quote', () {
      final text = decode('> a**b**');

      expect(text.plain, 'ab');
      expect(text.entities, [
        const Entity(0, 2, EntityKind.quote),
        const Entity(1, 1, _bold),
      ]);
    });
  });

  group('ADR 017: no auto-detection', () {
    test('a bare URL and a bare @name stay plain text', () {
      const text = 'see https://example.com and www.example.com or @alice';

      expect(decode(text), const RichText.plain(text));
    });
  });

  group('a link label holding code', () {
    test('keeps the link and reads the code as text', () {
      expect(
        decode('[`a`](https://u)'),
        RichText('a', const [Entity(0, 1, EntityKind.link('https://u'))]),
      );
      expect(
        decode('[x `a` y](https://u)'),
        RichText('x a y', const [Entity(0, 5, EntityKind.link('https://u'))]),
      );
    });
  });

  group('never throws', () {
    test('on markup that would break the entity rules', () {
      for (final input in const [
        '[**a](u)**',
        '`**a`**',
        '**[a**](u)',
        '[a](mention:)',
        '[@x](mention:x)**',
        '![](unicode:1F44D)',
        '__a__b__c__',
        '*****',
        '~~~~~~',
        '> > a',
        '>',
        '\n>\n',
        '[`a`](u)',
        '[x `a` y](u)',
      ]) {
        expect(() => decode(input), returnsNormally, reason: input);
      }
    });
  });
}
