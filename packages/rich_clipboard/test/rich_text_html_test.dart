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
const _bullet = EntityKind.list(listKind: EntityListKind.bullet);
const _ordered = EntityKind.list(listKind: EntityListKind.ordered);
const _nested = EntityKind.list(listKind: EntityListKind.bullet, depth: 1);
const _alice = EntityKind.username('alice');
const _dart = EntityKind.hashtag('dart');

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
      'links of any scheme, and without one',
      _text('app site chat', [
        ('app', const EntityKind.link('myapp://open?id=1')),
        ('site', const EntityKind.link('example.com/page')),
        ('chat', const EntityKind.link('tg://resolve?domain=chat')),
      ]),
    );
    roundTrips(
      'a quote, a link and a style over one range',
      _text('all three', [
        ('all three', EntityKind.quote),
        ('all three', const EntityKind.link('https://example.com')),
        ('all three', EntityKind.bold),
      ]),
    );
    roundTrips(
      'whitespace, markup characters and scripts kept exactly',
      const RichText.plain(
        '  two  spaces\ttab  nbsp\n\n< & > " \' ф 中 '
        '\u{1F44D}\u{1F3FB} \u{1F469}‍\u{1F4BB} ',
      ),
    );

    roundTrips(
      'a username and a hashtag, with a style across one',
      _text('hi @alice and #dart now', [
        ('hi @al', EntityKind.bold),
        ('@alice', _alice),
        ('#dart', _dart),
      ]),
    );
    roundTrips(
      'a username next to a link and a mention',
      _text('@alice[l]@bob', [
        ('@alice', _alice),
        ('[l]', const EntityKind.link('https://example.com')),
        ('@bob', const EntityKind.mention('bob')),
      ]),
    );
    roundTrips(
      'two list items, a bullet and an ordered one',
      _text('one\ntwo', [('one', _bullet), ('two', _ordered)]),
    );
    roundTrips(
      'nested items, a jump of two levels, and a return',
      _text('a\nb\nc\nd\ne', [
        ('a', _bullet),
        ('b', _nested),
        (
          'c',
          const EntityKind.list(listKind: EntityListKind.ordered, depth: 3),
        ),
        ('d', _ordered),
        (
          'e',
          const EntityKind.list(listKind: EntityListKind.ordered, depth: 2),
        ),
      ]),
    );
    roundTrips(
      'items with styles, a link and a soft break, beside plain lines',
      _text('intro\nan item\ncontinued\nnext one\nafter', [
        ('an item\ncontinued', _bullet),
        ('item', EntityKind.bold),
        ('next one', _bullet),
        ('next', const EntityKind.link('https://example.com')),
      ]),
    );
    roundTrips(
      'items with empty lines inside and at the end',
      _text('one\n\ntwo\nthree\n', [
        ('one\n', _bullet),
        ('two', _bullet),
        ('three\n', _ordered),
      ]),
    );
    roundTrips(
      'items between a quote and a code block',
      _text('quote\nitem\nitem\ncode', [
        ('quote', EntityKind.quote),
        ('item\nitem', _ordered),
        ('code', const EntityKind.codeBlock()),
      ]),
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
        EntityKind.link('myapp://open'),
        EntityKind.link('example.com/a'),
        EntityKind.mention('bob'),
        EntityKind.inlineContent(_rocket),
        EntityKind.codeBlock(language: 'dart'),
        EntityKind.codeBlock(),
        _alice,
        _dart,
        _bullet,
        _ordered,
        _nested,
        EntityKind.list(listKind: EntityListKind.ordered, depth: 3),
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
      expect(checked, greaterThan(800));
    });
  });

  test('reads its own HTML out of the document a platform wraps it in', () {
    // Windows' HTML Format wraps a copy in a document of its own, with line
    // breaks around the fragment.
    final text = _text('bold\nline', [('bold', EntityKind.bold)]);
    final wrapped =
        '<html><body>\r\n<!--StartFragment-->'
        '${RichTextHtml.encode(text)}'
        '<!--EndFragment-->\r\n</body></html>';

    expect(RichTextHtml.decode(wrapped), text);
  });

  group('encode', () {
    test('writes a long text with many entities in time linear in its '
        'size', () {
      const word = 'word ';
      final plain = word * 50000;
      final text = RichText(plain, [
        for (var i = 0; i < 50000; i++)
          Entity(
            i * word.length,
            4,
            i.isEven ? EntityKind.bold : EntityKind.code,
          ),
      ]);
      final timer = Stopwatch()..start();

      final html = RichTextHtml.encode(text);

      timer.stop();
      expect(RichTextHtml.decode(html), text);
      expect(timer.elapsed, lessThan(const Duration(seconds: 2)));
    });

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

    test('reads paragraphs and breaks as lines, and list items as items, '
        'collapsing whitespace', () {
      expect(
        RichTextHtml.decode(
          '<html><head><title>t</title><style>p{}</style></head><body>\n'
          '  <p>first   paragraph\n line</p><p>second</p>'
          '<ul><li>one</li><li>two</li></ul>a<br>b<br><br>c'
          '<script>ignored()</script>\n</body></html>',
        ),
        _text('first paragraph line\nsecond\none\ntwo\na\nb\n\nc', [
          ('one', _bullet),
          ('two', _bullet),
        ]),
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

    test('reads mention ids and content keys from its own HTML only', () {
      // A page can carry the attributes over any text: a mention that shows
      // one name and notifies another.
      expect(
        RichTextHtml.decode(
          '<p>hi <span data-mention-id="victim">@alice</span> '
          '<span data-content-key="document:rocket">\u{1F680}</span></p>',
        ),
        const RichText.plain('hi @alice \u{1F680}'),
      );
    });

    test('keeps no unsafe link, even in HTML marked as its own', () {
      expect(
        RichTextHtml.decode(
          '<span data-rich-text="1"><a href="javascript:alert(1)">a</a> '
          '<a href=" JavaScript:alert(1)">b</a> '
          '<a href="data:text/html,x">c</a> <a href="myapp://x">d</a></span>',
        ),
        _text('a b c d', [('d', const EntityKind.link('myapp://x'))]),
      );
    });

    test('reads a class among others, whatever whitespace parts them', () {
      expect(
        RichTextHtml.decode('x <span class="a\ttg-spoiler\nb">y</span>'),
        _text('x y', [('y', EntityKind.spoiler)]),
      );
    });

    test('reads a large document in time linear in its size', () {
      final page = StringBuffer('<div>');
      for (var i = 0; i < 20000; i++) {
        page.write('<p>line <b>$i</b> of <i>many</i> </p>');
      }
      page.write('</div>');
      final timer = Stopwatch()..start();

      final text = RichTextHtml.decode(page.toString());

      timer.stop();
      expect(text.plain.split('\n'), hasLength(20000));
      expect(timer.elapsed, lessThan(const Duration(seconds: 5)));
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

  group('encode of the new kinds', () {
    test('writes a username and a hashtag as links to their scheme', () {
      final html = RichTextHtml.encode(
        _text('@alice #dart', [('@alice', _alice), ('#dart', _dart)]),
      );

      expect(html, contains('<a href="username:alice">@alice</a>'));
      expect(html, contains('<a href="hashtag:dart">#dart</a>'));
    });

    test('writes items as one list, without a br between consecutive ones', () {
      final html = RichTextHtml.encode(
        _text('one\ntwo\nthree', [
          ('one', _bullet),
          ('two', _bullet),
          ('three', _ordered),
        ]),
      );

      expect(
        html,
        contains('<ul><li>one</li><li>two</li></ul><ol><li>three</li></ol>'),
      );
      expect(html, isNot(contains('<br>')));
    });

    test('nests a deeper item inside the item before it', () {
      final html = RichTextHtml.encode(
        _text('a\nb\nc', [('a', _bullet), ('b', _nested), ('c', _bullet)]),
      );

      expect(
        html,
        contains('<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>'),
      );
    });

    test('keeps a br where a line break is not between two items', () {
      final html = RichTextHtml.encode(
        _text('one\nplain\ntwo', [('one', _bullet), ('two', _bullet)]),
      );

      expect(html, contains('<ul><li>one</li></ul><br>plain<br><ul><li>two'));
    });
  });

  group('decode of lists', () {
    test('reads a web list into items', () {
      expect(
        RichTextHtml.decode('<ul><li>one</li><li>two</li></ul>'),
        _text('one\ntwo', [('one', _bullet), ('two', _bullet)]),
      );
      expect(
        RichTextHtml.decode('<ol><li>one</li><li>two</li></ol>'),
        _text('one\ntwo', [('one', _ordered), ('two', _ordered)]),
      );
    });

    test('reads nesting as depth, an item as its text up to a nested list', () {
      expect(
        RichTextHtml.decode(
          '<ul>\n  <li>a\n    <ol><li>b</li><li>c <b>bold</b></li></ol>\n'
          '  </li>\n  <li>z</li>\n</ul>',
        ),
        _text('a\nb\nc bold\nz', [
          ('a', _bullet),
          (
            'b',
            const EntityKind.list(listKind: EntityListKind.ordered, depth: 1),
          ),
          (
            'c bold',
            const EntityKind.list(listKind: EntityListKind.ordered, depth: 1),
          ),
          ('bold', EntityKind.bold),
          ('z', _bullet),
        ]),
      );
    });

    test('an item holding paragraphs is one item of several lines', () {
      expect(
        RichTextHtml.decode(
          '<ul><li><p>one</p><p>two</p></li><li>three</li></ul>',
        ),
        _text('one\ntwo\nthree', [('one\ntwo', _bullet), ('three', _bullet)]),
      );
    });

    test('a depth beyond three is three', () {
      expect(
        RichTextHtml.decode(
          '<ul><li><ul><li><ul><li><ul><li><ul><li>deep</li></ul></li></ul>'
          '</li></ul></li></ul></li></ul>',
        ).entities,
        [
          const Entity(
            0,
            4,
            EntityKind.list(listKind: EntityListKind.bullet, depth: 3),
          ),
        ],
      );
    });

    test('an item with no text is no item, and a stray li is a bullet', () {
      expect(
        RichTextHtml.decode('<ul><li></li><li>x</li></ul>a<li>y</li>'),
        _text('x\na\ny', [('x', _bullet), ('y', _bullet)]),
      );
    });

    test('an item next to a quote or a code block yields to it', () {
      expect(
        RichTextHtml.decode('<ul><li><blockquote>q</blockquote></li></ul>'),
        _text('q', [('q', EntityKind.quote)]),
      );
      expect(
        RichTextHtml.decode('<ul><li><pre>code</pre></li></ul>'),
        _text('code', [('code', const EntityKind.codeBlock())]),
      );
    });

    test('never throws on lists in odd places', () {
      for (final html in [
        '<ul><ul><li>x</li></ul></ul>',
        '<li>a<li>b',
        '<ul><li><code><li>x</li></code></li></ul>',
        '<span data-rich-text="1"><ul><li>a</li></span>',
        '<span data-rich-text="1"><li><li>a</li></li></span>',
        '<ol><li><span data-mention-id="x"><li>z</li></span></li></ol>',
      ]) {
        expect(() => RichTextHtml.decode(html), returnsNormally, reason: html);
      }
    });
  });

  group('usernames and hashtags in HTML', () {
    test('are read from this app\'s own HTML', () {
      final text = _text('@alice', [('@alice', _alice)]);

      expect(RichTextHtml.decode(RichTextHtml.encode(text)), text);
    });

    test('are only a link, or text, in another app\'s HTML', () {
      expect(
        RichTextHtml.decode(
          '<a href="username:alice">@alice</a> '
          '<a href="hashtag:dart">#dart</a> '
          '<a href="https://example.com/u/alice">@alice</a>',
        ),
        RichText('@alice #dart @alice', const [
          Entity(13, 6, EntityKind.link('https://example.com/u/alice')),
        ]),
      );
    });

    test('an own href with no name, or a link in their scheme, is text', () {
      final own = RichTextHtml.encode(const RichText.plain('x'));

      for (final href in ['username:', 'hashtag:', 'mention:x']) {
        expect(
          RichTextHtml.decode(
            own.replaceFirst('>x<', '><a href="$href">x</a><'),
          ),
          const RichText.plain('x'),
          reason: href,
        );
      }
    });
  });
}
