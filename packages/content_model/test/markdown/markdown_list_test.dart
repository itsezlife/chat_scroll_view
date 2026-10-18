/// Lists in markdown: the spelling the vendored encoder stored, and the round
/// trip of what this package writes.
///
/// **Seam:** `RichTextMarkdown.encode` and `decode`.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

const _bullet = EntityKind.list(listKind: EntityListKind.bullet);
const _ordered = EntityKind.list(listKind: EntityListKind.ordered);

EntityKind _item(EntityListKind kind, [int depth = 0]) =>
    EntityKind.list(listKind: kind, depth: depth);

RichText decode(String markdown) => RichTextMarkdown.decode(markdown);

String encode(RichText text) => RichTextMarkdown.encode(text);

/// [lines] as text with one item per line: `(text, kind, depth)`.
RichText items(
  List<(String, EntityListKind, int)> lines, [
  List<Entity> more = const [],
]) {
  final plain = StringBuffer();
  final entities = <Entity>[...more];
  for (final (text, kind, depth) in lines) {
    if (plain.isNotEmpty) plain.write('\n');
    entities.add(Entity(plain.length, text.length, _item(kind, depth)));
    plain.write(text);
  }
  return RichText(plain.toString(), entities);
}

void expectRoundTrip(RichText text) {
  final markdown = encode(text);

  expect(
    decode(markdown),
    text,
    reason: 'through ${markdown.replaceAll('\n', r'\n')}',
  );
}

void main() {
  const bullet = EntityListKind.bullet;
  const ordered = EntityListKind.ordered;

  group('encode', () {
    test('writes a bullet as "- " and an item of a number as "n. "', () {
      expect(
        encode(items([('one', bullet, 0), ('two', bullet, 0)])),
        '- one\n- two',
      );
      expect(
        encode(items([('one', ordered, 0), ('two', ordered, 0)])),
        '1. one\n2. two',
      );
    });

    test('indents two spaces a level', () {
      expect(
        encode(
          items([
            ('a', bullet, 0),
            ('b', bullet, 1),
            ('c', ordered, 2),
            ('d', bullet, 3),
          ]),
        ),
        '- a\n  - b\n    1. c\n      - d',
      );
    });

    test('writes a soft break inside an item as two spaces and a break', () {
      final text = RichText('one\ncontinued\nnext', const [
        Entity(0, 13, _bullet),
        Entity(14, 4, _bullet),
      ]);

      expect(encode(text), '- one  \ncontinued\n- next');
    });

    test('numbers an ordered run from 1, whatever the stored numbers were', () {
      // The number is derived: a gap does not leave a gap.
      final withThree = RichText('a\nb\nc', const [
        Entity(0, 1, _ordered),
        Entity(2, 1, _ordered),
        Entity(4, 1, _ordered),
      ]);

      expect(encode(withThree), '1. a\n2. b\n3. c');
      expect(encode(withThree.delete(2, 4)), '1. a\n2. c');
    });

    test('a bullet, a shallower item or a plain line ends a numbered run', () {
      expect(
        encode(
          items([
            ('a', ordered, 0),
            ('b', ordered, 0),
            ('x', bullet, 0),
            ('c', ordered, 0),
            ('d', ordered, 1),
            ('e', ordered, 1),
            ('f', ordered, 0),
            ('g', ordered, 1),
          ]),
        ),
        '1. a\n2. b\n- x\n1. c\n  1. d\n  2. e\n2. f\n  1. g',
      );
      expect(
        encode(
          RichText('a\nplain\nb', const [
            Entity(0, 1, _ordered),
            Entity(8, 1, _ordered),
          ]),
        ),
        '1. a\nplain\n1. b',
      );
    });

    test('writes styles inside an item', () {
      final text = items(
        [('one two', ordered, 0)],
        const [Entity(4, 3, EntityKind.bold)],
      );

      expect(encode(text), '1. one **two**');
    });

    test('escapes text that would read as a marker', () {
      final text = items([('- x', bullet, 0)]);

      expect(decode(encode(text)), text);
      expect(
        encode(const RichText.plain('- x\n3. x')),
        r'\- x'
        '\n'
        r'3\. x',
      );
    });
  });

  group('decode: what the vendored encoder stored', () {
    // Research 03 section 3.1: the shapes job_solution's composer wrote.
    test('"- one" and "1. one"', () {
      expect(decode('- one'), RichText('one', const [Entity(0, 3, _bullet)]));
      expect(decode('1. one'), RichText('one', const [Entity(0, 3, _ordered)]));
    });

    test('"3. **one**" is an ordered item with bold; the 3 is not kept', () {
      expect(
        decode('3. **one**'),
        RichText('one', const [
          Entity(0, 3, _ordered),
          Entity(0, 3, EntityKind.bold),
        ]),
      );
    });

    test('nested two-space indents', () {
      expect(
        decode('- a\n  - b\n    1. c'),
        items([('a', bullet, 0), ('b', bullet, 1), ('c', ordered, 2)]),
      );
    });

    test('a soft break (two spaces, then the break) keeps the item going', () {
      expect(
        decode('- one  \ncontinued\n- next'),
        RichText('one\ncontinued\nnext', const [
          Entity(0, 13, _bullet),
          Entity(14, 4, _bullet),
        ]),
      );
    });

    test('other markers, ")" numbers and tab indents are read as items', () {
      expect(
        decode('* a\n+ b\n2) c\n\t- d'),
        items([
          ('a', bullet, 0),
          ('b', bullet, 0),
          ('c', ordered, 0),
          ('d', bullet, 1),
        ]),
      );
    });

    test('nesting deeper than three levels stays at three', () {
      expect(decode('        - deep'), items([('deep', bullet, 3)]));
    });

    test('an escaped marker stays text', () {
      expect(decode(r'\- x'), const RichText.plain('- x'));
      expect(decode(r'3\. x'), const RichText.plain('3. x'));
    });

    test('text that only looks like a marker stays text', () {
      for (final text in const [
        '-x',
        '-> arrow',
        '--- rule',
        '**bold** a',
        '10.5 percent',
        '1.5',
        '1234567890. ten digits',
        '         - nine columns in',
      ]) {
        final decoded = decode(text);
        expect(
          decoded.entities.where((e) => e.kind is EntityKind$List),
          isEmpty,
          reason: text,
        );
      }
    });

    test('a list between paragraphs, a quote and a fence', () {
      expect(
        decode('before\n- a\n- b\nafter'),
        RichText('before\na\nb\nafter', const [
          Entity(7, 1, _bullet),
          Entity(9, 1, _bullet),
        ]),
      );
      expect(
        decode('> q\n\n- a'),
        RichText('q\na', const [
          Entity(0, 1, EntityKind.quote),
          Entity(2, 1, _bullet),
        ]),
      );
      expect(
        decode('- a\n```dart\nx\n```'),
        RichText('a\nx', const [
          Entity(0, 1, _bullet),
          Entity(2, 1, EntityKind.codeBlock(language: 'dart')),
        ]),
      );
    });

    test('an item with no text is an empty line', () {
      expect(
        decode('- a\n-\n- b'),
        RichText('a\n\nb', const [
          Entity(0, 1, _bullet),
          Entity(3, 1, _bullet),
        ]),
      );
      expect(decode('-'), RichText.empty);
    });

    test('never throws on whatever markers and spaces it is given', () {
      for (final text in const [
        '- ',
        '-  ',
        '-   \n',
        '1.  \n\n  ',
        '- a  \n',
        '- a  \n> q',
        '- a  \n- b  \n- c',
        r'- a \ ',
        '  \n  - ',
        '- [ ] todo',
      ]) {
        final decoded = decode(text);

        expect(RichText(decoded.plain, decoded.entities), decoded);
      }
    });
  });

  group('round trip', () {
    test('bullet and ordered lists at depths 0 to 3', () {
      for (final kind in EntityListKind.values) {
        for (var depth = 0; depth <= 3; depth++) {
          expectRoundTrip(items([('one', kind, depth), ('two', kind, depth)]));
        }
      }
    });

    test('items with styles, links, mentions, code and inline content', () {
      expectRoundTrip(
        items(
          [('one two three', bullet, 0), ('a b c', ordered, 1)],
          [
            const Entity(4, 3, EntityKind.bold),
            const Entity(8, 5, EntityKind.italic),
            const Entity(14, 1, EntityKind.link('https://x/a_(b)')),
            const Entity(16, 1, EntityKind.mention('7')),
            const Entity(18, 1, EntityKind.code),
          ],
        ),
      );
    });

    test('soft breaks inside an item', () {
      expectRoundTrip(
        RichText('one\ncontinued\nmore\nnext', const [
          Entity(0, 18, _bullet),
          Entity(19, 4, _ordered),
        ]),
      );
    });

    test('a soft break after an empty line, and an empty last line', () {
      expectRoundTrip(
        RichText('one\n\ntwo\nnext', const [
          Entity(0, 8, _bullet),
          Entity(9, 4, _bullet),
        ]),
      );
      expectRoundTrip(RichText('one\n', const [Entity(0, 4, _bullet)]));
    });

    test('an item whose lines end in spaces', () {
      for (final plain in const [
        'a  ',
        'a   ',
        'a ',
        'a  \nb',
        'a  \nb  ',
        r'a\ ',
        r'a\  ',
        '  ',
      ]) {
        expectRoundTrip(
          RichText('$plain\nnext', [Entity(0, plain.length, _bullet)]),
        );
        expectRoundTrip(
          RichText('$plain\nnext', [
            Entity(0, plain.length, _bullet),
            Entity(plain.length + 1, 4, _ordered),
          ]),
        );
        expectRoundTrip(RichText(plain, [Entity(0, plain.length, _bullet)]));
      }
    });

    test('mixed bullet and ordered siblings', () {
      expectRoundTrip(
        items([
          ('a', bullet, 0),
          ('b', ordered, 0),
          ('c', ordered, 0),
          ('d', bullet, 0),
          ('e', ordered, 1),
          ('f', bullet, 1),
          ('g', ordered, 0),
          ('h', ordered, 3),
        ]),
      );
    });

    test('items beside paragraphs, quotes and code blocks', () {
      expectRoundTrip(
        RichText('intro\nitem\nitem two\nquote\nafter\ncode\ntail', const [
          Entity(6, 4, _bullet),
          Entity(11, 8, _ordered),
          Entity(20, 5, EntityKind.quote),
          Entity(32, 4, EntityKind.codeBlock()),
        ]),
      );
      expectRoundTrip(
        RichText('q\nitem', const [
          Entity(0, 1, EntityKind.quote),
          Entity(2, 4, _bullet),
        ]),
      );
    });

    test('item text that looks like a marker, a quote or a fence', () {
      for (final text in const [
        '- x',
        '3. x',
        '> q',
        '```',
        '# h',
        '* x',
        '1) x',
        '- x\n- y',
      ]) {
        expectRoundTrip(RichText(text, [Entity(0, text.length, _bullet)]));
        expectRoundTrip(
          RichText('$text\nb', [Entity(0, text.length, _ordered)]),
        );
      }
    });

    test('a list item next to a bang before a link', () {
      expectRoundTrip(
        RichText('hi!\nx', const [
          Entity(0, 3, _bullet),
          Entity(4, 1, EntityKind.link('u')),
        ]),
      );
    });
  });
}
