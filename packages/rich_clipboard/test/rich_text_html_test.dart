// HTML fragments are joined without whitespace on purpose: whitespace between
// tags is part of what the decoder is tested on.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_clipboard/rich_clipboard.dart';

/// [plain] with [kind] over each of [parts], found in order.
RichText _text(String plain, List<(String, EntityKind)> parts) {
  var from = 0;
  return RichText(plain, [
    for (final (part, kind) in parts)
      () {
        final at = plain.indexOf(part, from);
        assert(at >= 0, '"$part" is not in "$plain" after $from');
        from = at;
        return Entity(at, part.length, kind);
      }(),
  ]);
}

const _rocket = ContentKey.document('rocket');

void main() {
  group('round trip', () {
    void roundTrips(String description, RichText text) {
      test(description, () {
        expect(RichTextHtml.decode(RichTextHtml.encode(text)), text);
      });
    }

    roundTrips('plain text', const RichText.plain('just words'));
    roundTrips('empty text', RichText.empty);
    roundTrips(
      'every style',
      _text('bold italic under strike hidden code', [
        ('bold', EntityKind.bold),
        ('italic', EntityKind.italic),
        ('under', EntityKind.underline),
        ('strike', EntityKind.strike),
        ('hidden', EntityKind.spoiler),
        ('code', EntityKind.code),
      ]),
    );
    roundTrips(
      'styles that overlap without nesting',
      _text('one two three', [
        ('one two', EntityKind.bold),
        ('two three', EntityKind.italic),
      ]),
    );
    roundTrips(
      'code inside bold, and a link around italic',
      _text('see this code and that link', [
        ('this code and', EntityKind.bold),
        ('code', EntityKind.code),
        ('that link', const EntityKind.link('https://example.com/?a=1&b="2"')),
        ('link', EntityKind.italic),
      ]),
    );
    roundTrips(
      'a mention and custom emoji, two of the same side by side',
      _text('hi @alice \u{1F680}\u{1F680}', [
        ('@alice', const EntityKind.mention('alice')),
        ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
        ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
      ]),
    );
    roundTrips(
      'quotes at the start, the middle and the end, with empty lines',
      _text('first\nsecond\n\nplain\nthird\nfourth', [
        ('first\nsecond', EntityKind.quote),
        ('third\nfourth', EntityKind.quote),
      ]),
    );
    roundTrips(
      'two quotes on consecutive lines',
      _text('one\ntwo', [('one', EntityKind.quote), ('two', EntityKind.quote)]),
    );
    roundTrips(
      'bold inside a quote',
      _text('a quoted bold word', [
        ('a quoted bold word', EntityKind.quote),
        ('bold', EntityKind.bold),
      ]),
    );
    roundTrips(
      'a code block with its language between lines of text',
      _text('see\nmain() {\n  <b>\n}\nend', [
        ('main() {\n  <b>\n}', const EntityKind.codeBlock(language: 'dart')),
      ]),
    );
    roundTrips(
      'whitespace, markup characters and scripts kept exactly',
      const RichText.plain(
        '  two  spaces\ttab  nbsp\n\n< & > " \' ф 中 '
        '\u{1F44D}\u{1F3FB} \u{1F469}‍\u{1F4BB} ',
      ),
    );

    test('holds for random texts', () {
      final random = Random(7);
      const kinds = [
        EntityKind.bold,
        EntityKind.italic,
        EntityKind.underline,
        EntityKind.strike,
        EntityKind.spoiler,
        EntityKind.code,
        EntityKind.quote,
        EntityKind.link('https://example.com'),
        EntityKind.mention('bob'),
        EntityKind.inlineContent(_rocket),
        EntityKind.codeBlock(language: 'dart'),
        EntityKind.codeBlock(),
      ];
      const pieces = ['a', 'b c', ' ', '\n', '  ', '\u{1F680}', '<', '&', 'é'];
      var checked = 0;
      for (var round = 0; round < 3000; round++) {
        final plain = [
          for (var i = random.nextInt(12); i >= 0; i--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        final entities = [
          for (var i = random.nextInt(5); i > 0; i--)
            if (plain.isNotEmpty)
              () {
                final start = random.nextInt(plain.length);
                return Entity(
                  start,
                  1 + random.nextInt(plain.length - start),
                  kinds[random.nextInt(kinds.length)],
                );
              }(),
        ];
        final RichText text;
        try {
          text = RichText(plain, entities);
          // Random entities often cannot coexist; RichText says so with an
          // ArgumentError.
          // ignore: avoid_catching_errors
        } on ArgumentError {
          continue;
        }
        expect(
          RichTextHtml.decode(RichTextHtml.encode(text)),
          text,
          reason: RichTextHtml.encode(text),
        );
        checked++;
      }
      expect(checked, greaterThan(1000));
    });
  });

  group('encode', () {
    test('writes the elements other apps know', () {
      final html = RichTextHtml.encode(
        _text('b i u s spoiler code link', [
          ('b', EntityKind.bold),
          ('i', EntityKind.italic),
          ('u', EntityKind.underline),
          ('s', EntityKind.strike),
          ('spoiler', EntityKind.spoiler),
          ('code', EntityKind.code),
          ('link', const EntityKind.link('https://example.com')),
        ]),
      );

      for (final element in [
        '<b>b</b>',
        '<i>i</i>',
        '<u>u</u>',
        '<s>s</s>',
        '<tg-spoiler>spoiler</tg-spoiler>',
        '<code>code</code>',
        '<a href="https://example.com">link</a>',
      ]) {
        expect(html, contains(element));
      }
    });

    test('writes a custom emoji as its alternative text, keyed in an '
        'attribute', () {
      final html = RichTextHtml.encode(
        _text('\u{1F680}', [
          ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
        ]),
      );

      expect(
        html,
        contains('<span data-content-key="document:rocket">\u{1F680}</span>'),
      );
    });
  });

  group('decode of other apps\' HTML', () {
    test('reads the common formatting elements', () {
      expect(
        RichTextHtml.decode(
          'one <strong>two</strong> <em>three</em> <ins>four</ins> '
          '<del>five</del> <strike>six</strike> <tt>seven</tt> '
          '<a href="https://example.com">eight</a>',
        ),
        _text('one two three four five six seven eight', [
          ('two', EntityKind.bold),
          ('three', EntityKind.italic),
          ('four', EntityKind.underline),
          ('five', EntityKind.strike),
          ('six', EntityKind.strike),
          ('seven', EntityKind.code),
          ('eight', const EntityKind.link('https://example.com')),
        ]),
      );
    });

    test('reads CSS weights, styles and decorations, and their negation', () {
      expect(
        RichTextHtml.decode(
          // Google Docs wraps a whole copy in a b that is not bold.
          '<b style="font-weight:normal" id="docs-internal-guid-1">'
          '<span style="font-weight:700">heavy</span> '
          '<span style="font-style:italic">slanted</span> '
          '<span style="text-decoration:underline">under</span> '
          '<span style="text-decoration-line: line-through">struck</span> '
          'plain</b>',
        ),
        _text('heavy slanted under struck plain', [
          ('heavy', EntityKind.bold),
          ('slanted', EntityKind.italic),
          ('under', EntityKind.underline),
          ('struck', EntityKind.strike),
        ]),
      );
    });

    test('reads paragraphs, breaks and list items as lines, collapsing '
        'whitespace', () {
      expect(
        RichTextHtml.decode(
          '<html><head><title>t</title><style>p{}</style></head><body>\n'
          '  <p>first   paragraph\n line</p><p>second</p>'
          '<ul><li>one</li><li>two</li></ul>a<br>b<br><br>c'
          '<script>ignored()</script>\n</body></html>',
        ),
        const RichText.plain(
          'first paragraph line\nsecond\none\ntwo\na\nb\n\nc',
        ),
      );
    });

    test('keeps whitespace inside pre and pre-wrap', () {
      expect(
        RichTextHtml.decode(
          '<pre>a  b\n  c</pre><span style="white-space:pre-wrap">d  e</span>',
        ).plain,
        'a  b\n  c\nd  e',
      );
    });

    test('drops a style that covers the whole of another app\'s text', () {
      expect(
        RichTextHtml.decode('<b>all of it <i>bold</i></b>'),
        _text('all of it bold', [('bold', EntityKind.italic)]),
      );
    });

    test('keeps only links with a scheme it can follow', () {
      expect(
        RichTextHtml.decode(
          'x <a href="javascript:alert(1)">bad</a> '
          '<a href="relative/path">rel</a> '
          '<a href="mailto:a@b.c">mail</a>',
        ),
        _text('x bad rel mail', [
          ('mail', const EntityKind.link('mailto:a@b.c')),
        ]),
      );
    });

    test('reads the reference Android client\'s tags', () {
      expect(
        RichTextHtml.decode(
          'a <animated-emoji data-document-id="5368324170671202286">'
          '&#128640;</animated-emoji> <spoiler>hidden</spoiler> '
          '<pre lang="dart">code</pre><blockquote>quoted</blockquote>',
        ),
        _text('a \u{1F680} hidden\ncode\nquoted', [
          (
            '\u{1F680}',
            const EntityKind.inlineContent(
              ContentKey.document('5368324170671202286'),
            ),
          ),
          ('hidden', EntityKind.spoiler),
          ('code', const EntityKind.codeBlock(language: 'dart')),
          ('quoted', EntityKind.quote),
        ]),
      );
    });

    test('reads a code block\'s language as code sites write it', () {
      for (final html in [
        '<pre language="go">x</pre>',
        '<pre data-language="go">x</pre>',
        '<pre><code class="hljs language-go">x</code></pre>',
      ]) {
        expect(
          RichTextHtml.decode(html),
          _text('x', [('x', const EntityKind.codeBlock(language: 'go'))]),
          reason: html,
        );
      }
      expect(
        RichTextHtml.decode('<pre>a  <b>b</b>\n c</pre>'),
        _text('a  b\n c', [('a  b\n c', const EntityKind.codeBlock())]),
      );
    });

    test('reads the reference desktop client\'s tags', () {
      expect(
        RichTextHtml.decode(
          '<html><body>x <tg-spoiler>a</tg-spoiler> '
          '<span class="tg-spoiler">b</span> <details>c</details></body></html>',
        ),
        _text('x a b\nc', [
          ('a', EntityKind.spoiler),
          ('b', EntityKind.spoiler),
          ('c', EntityKind.quote),
        ]),
      );
    });

    test('never throws, keeping the text of what it cannot read', () {
      for (final html in [
        '<b><i>unclosed',
        '</b>stray close<b>',
        '<a href="https://e.com"><span data-mention-id="x">clash</span></a>',
        '<code><span data-content-key="document:x">\u{1F680}</span></code>',
        '<span data-content-key="not a key">alt</span>',
        '<animated-emoji data-document-id="">x</animated-emoji>',
        '',
        '<<<>>>&&&',
      ]) {
        expect(() => RichTextHtml.decode(html), returnsNormally, reason: html);
      }
      expect(RichTextHtml.decode('<b><i>unclosed').plain, 'unclosed');
    });
  });
}
