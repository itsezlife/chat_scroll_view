import 'dart:math';

import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

const _bold = EntityKind.bold;
const _italic = EntityKind.italic;

/// Encodes [text] and decodes the result.
RichText roundTrip(RichText text) =>
    RichTextMarkdown.decode(RichTextMarkdown.encode(text));

void expectRoundTrip(RichText text) {
  final markdown = RichTextMarkdown.encode(text);

  expect(
    RichTextMarkdown.decode(markdown),
    text,
    reason: 'through ${markdown.replaceAll('\n', r'\n')}',
  );
}

void main() {
  const thumbsUp = '\u{1F44D}';
  const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
  const umbrella = '☂️';

  group('round trip', () {
    test('plain text, including text full of markup characters', () {
      for (final text in const [
        '',
        'hello',
        'a\nb\n\nc\n',
        r'*_`[]()\!#>-+|~=.<&',
        '5 * 6 = 30, a_b, a__b, __init__, ~~, ||, ==',
        '# h\n- l\n+ l\n> q\n| t\n1. o\n2) p\n~~~\n```\n===\n***\n---\n___',
        'https://example.com/a_b?x=1&y=[2] @alice www.x.org',
        '$family $thumbsUp $umbrella é́ 中文',
      ]) {
        expectRoundTrip(RichText.plain(text));
      }
    });

    test('every style on its own', () {
      for (final style in EntityStyle.values) {
        expectRoundTrip(
          RichText('say hello now', [Entity(4, 5, EntityKind.style(style))]),
        );
      }
    });

    test('a style over text with markup characters', () {
      expectRoundTrip(RichText('a*b_c`d[e]f', const [Entity(0, 11, _bold)]));
      expectRoundTrip(
        RichText('a*b_c`d[e]f', const [Entity(0, 11, EntityKind.code)]),
      );
      expectRoundTrip(RichText('~x', const [Entity(1, 1, EntityKind.strike)]));
      expectRoundTrip(RichText('x|', const [Entity(0, 1, EntityKind.spoiler)]));
    });

    test('emoji, ZWJ sequences, FE0F and surrogate pairs inside styles', () {
      final text = RichText('a$thumbsUp $family$umbrella z', const [
        Entity(0, 4, _bold),
        Entity(3, 10, _italic),
        Entity(3, 10, EntityKind.underline),
      ]);

      expectRoundTrip(text);
    });

    test('an entity edge between ZWJ-joined code points', () {
      expectRoundTrip(RichText('$family!', const [Entity(0, 2, _bold)]));
    });

    test('inline content with its alternative text', () {
      final text = RichText('a$thumbsUp b:)c ${family}x', const [
        Entity(1, 2, EntityKind.inlineContent(ContentKey.unicode(thumbsUp))),
        Entity(5, 2, EntityKind.inlineContent(ContentKey.document('5368'))),
        Entity(9, 5, EntityKind.inlineContent(ContentKey.unicode(family))),
        Entity(0, 17, _bold),
      ]);

      expectRoundTrip(text);
    });

    test('inline content keys of every variant', () {
      for (final key in const [
        ContentKey.unicode(thumbsUp),
        ContentKey.unicode(umbrella),
        ContentKey.unicode(family),
        ContentKey.document('5368'),
        ContentKey.external('https://x/a_(b)'),
        ContentKey.external('a b <c>'),
      ]) {
        expectRoundTrip(
          RichText('ab', [Entity(0, 2, EntityKind.inlineContent(key))]),
        );
      }
    });

    test('adjacent entities of different kinds', () {
      expectRoundTrip(
        RichText('aabbcc', const [
          Entity(0, 2, _bold),
          Entity(2, 2, _italic),
          Entity(4, 2, EntityKind.strike),
        ]),
      );
    });

    test('adjacent links to different targets and adjacent mentions', () {
      expectRoundTrip(
        RichText('abcd', const [
          Entity(0, 2, EntityKind.link('u')),
          Entity(2, 2, EntityKind.link('v')),
        ]),
      );
      expectRoundTrip(
        RichText('@a@b', const [
          Entity(0, 2, EntityKind.mention('a')),
          Entity(2, 2, EntityKind.mention('b')),
        ]),
      );
    });

    test('nested entities', () {
      expectRoundTrip(
        RichText('abcdefgh', const [
          Entity(0, 8, _bold),
          Entity(1, 6, _italic),
          Entity(2, 4, EntityKind.strike),
          Entity(3, 2, EntityKind.code),
        ]),
      );
    });

    test('partially overlapping entities', () {
      expectRoundTrip(
        RichText('abcdefgh', const [
          Entity(0, 5, _bold),
          Entity(3, 5, _italic),
          Entity(2, 4, EntityKind.underline),
        ]),
      );
    });

    test('styles over and inside a link', () {
      expectRoundTrip(
        RichText('abcdef', const [
          Entity(1, 3, EntityKind.link('https://x/y_(z)?a=b')),
          Entity(0, 3, _bold),
          Entity(2, 4, _italic),
        ]),
      );
    });

    test('a mention inside a style and next to one', () {
      expectRoundTrip(
        RichText('hi @alice, @bob_1!', const [
          Entity(3, 6, EntityKind.mention('alice')),
          Entity(11, 6, EntityKind.mention('bob_1')),
          Entity(0, 18, _bold),
        ]),
      );
    });

    test('quotes with styles, empty lines and surrounding text', () {
      expectRoundTrip(
        RichText('intro\nq1\n\nq2 *x*\noutro\nq3\n', const [
          Entity(6, 11, EntityKind.quote),
          Entity(9, 2, _bold),
          Entity(22, 3, EntityKind.quote),
        ]),
      );
      expectRoundTrip(RichText('q\n', const [Entity(0, 2, EntityKind.quote)]));
      expectRoundTrip(
        RichText('q\n\nrest', const [Entity(0, 1, EntityKind.quote)]),
      );
      expectRoundTrip(
        RichText('a\nb', const [
          Entity(0, 1, EntityKind.quote),
          Entity(2, 1, EntityKind.quote),
        ]),
      );
    });

    test('code containing backticks, spaces and markers', () {
      for (final code in [
        'a`b',
        '`',
        '``x``',
        ' a ',
        ' a',
        'a ',
        '  ',
        '*_~|',
      ]) {
        expectRoundTrip(
          RichText('<$code>', [Entity(1, code.length, EntityKind.code)]),
        );
      }
    });

    test('a bang before a link and before an image', () {
      expectRoundTrip(
        RichText('wow!x', const [Entity(4, 1, EntityKind.link('u'))]),
      );
      expectRoundTrip(
        RichText('!$thumbsUp', const [
          Entity(1, 2, EntityKind.inlineContent(ContentKey.unicode(thumbsUp))),
        ]),
      );
    });

    test('text a decoder could mistake for markup next to real markup', () {
      expectRoundTrip(
        RichText('a_b *c* ~d~ |e| =f=', const [
          Entity(4, 3, _bold),
          Entity(8, 3, EntityKind.strike),
          Entity(12, 3, EntityKind.spoiler),
        ]),
      );
    });
  });

  group('round trip of generated texts', () {
    const alphabet = [
      'a', 'b', ' ', '\n', '*', '_', '~', '|', '=', '`', '[', ']', '(', ')',
      '!', r'\', '>', '#', '-', '1', '.', '@', thumbsUp, family, umbrella,
      'é', //
    ];

    RichText? generate(Random random) {
      final plain = StringBuffer();
      final length = random.nextInt(14);
      for (var i = 0; i < length; i++) {
        plain.write(alphabet[random.nextInt(alphabet.length)]);
      }
      final source = plain.toString();
      final entities = <Entity>[];
      for (var i = random.nextInt(5); i > 0 && source.isNotEmpty; i--) {
        final offset = random.nextInt(source.length);
        final span = 1 + random.nextInt(source.length - offset);
        final kind = switch (random.nextInt(11)) {
          0 => EntityKind.bold,
          1 => EntityKind.italic,
          2 => EntityKind.underline,
          3 => EntityKind.strike,
          4 => EntityKind.spoiler,
          5 => EntityKind.code,
          6 => EntityKind.quote,
          7 => EntityKind.link('https://x/${random.nextInt(2)}_(a)'),
          8 => EntityKind.mention('m${random.nextInt(2)}'),
          9 => EntityKind.inlineContent(
            ContentKey.document('${random.nextInt(9)}'),
          ),
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

    test('decode(encode(x)) == x', () {
      final random = Random(20260716);
      var checked = 0;
      var withEntities = 0;
      for (var i = 0; i < 20000; i++) {
        final text = generate(random);
        if (text == null) continue;
        checked++;
        if (text.entities.isNotEmpty) withEntities++;
        expectRoundTrip(text);
      }

      expect(checked, greaterThan(3000));
      expect(withEntities, greaterThan(1500));
    });

    test('decode never throws and its result is already canonical', () {
      final random = Random(7);
      const pieces = [
        '*',
        '**',
        '***',
        '_',
        '__',
        '~~',
        '||',
        '`',
        '``',
        '[',
        ']',
        '(',
        ')',
        '](',
        '![',
        'mention:',
        'unicode:1F44D',
        '\n',
        '> ',
        '>',
        ' ',
        'a',
        'b',
        r'\',
        '<',
        '>',
        thumbsUp,
        'x',
      ];
      for (var i = 0; i < 20000; i++) {
        final markdown = [
          for (var j = random.nextInt(12); j > 0; j--)
            pieces[random.nextInt(pieces.length)],
        ].join();

        final text = RichTextMarkdown.decode(markdown);

        expect(RichText(text.plain, text.entities), text, reason: markdown);
      }
    });
  });
}
