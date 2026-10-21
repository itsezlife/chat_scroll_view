import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

const _bold = EntityKind.bold;
const _italic = EntityKind.italic;

String encode(String plain, [List<Entity> entities = const []]) =>
    RichTextMarkdown.encode(RichText(plain, entities));

void main() {
  group('plain text', () {
    test('without markers is written as it is', () {
      expect(
        encode('hello, world: 5 > 3 & done.'),
        'hello, world: 5 > 3 & done.',
      );
    });

    test('keeps line breaks, emoji, ZWJ sequences and FE0F untouched', () {
      const text = 'a\n\u{1F468}‍\u{1F469}‍\u{1F467} ☂️ b';

      expect(encode(text), text);
    });

    test('escapes the characters that would start markup', () {
      expect(encode(r'a*b`c[d]e\f'), r'a\*b\`c\[d\]e\\f');
      expect(encode('_x_'), r'\_x\_');
    });

    test('leaves an underscore inside a word alone', () {
      expect(encode('snake_case_name'), 'snake_case_name');
      expect(encode('snake__case'), r'snake\_\_case');
    });

    test('escapes ~, | and = only where a pair could form', () {
      expect(encode('a ~~ b || c == d'), 'a ~~ b || c == d');
      expect(encode('a~~b'), r'a\~\~b');
      expect(encode('a||b'), r'a\|\|b');
      expect(encode('x==y'), r'x\=\=y');
      expect(encode('~ | ='), '~ | =');
    });

    test('escapes block markers at the start of a line', () {
      expect(encode('# no'), r'\# no');
      expect(encode('- no'), r'\- no');
      expect(encode('+ no'), r'\+ no');
      expect(encode('> no'), r'\> no');
      expect(encode('| no'), r'\| no');
      expect(encode('1. no'), r'1\. no');
      expect(encode('12) no'), r'12\) no');
      expect(encode('ok\n# no\n  - no'), 'ok\n\\# no\n  \\- no');
      expect(encode('~~~'), r'\~\~\~');
    });

    test('does not escape markers in the middle of a line', () {
      expect(encode('a # b - c > d 1. e'), 'a # b - c > d 1. e');
    });

    test('does not escape a marker a link label starts the line with', () {
      // The line is written `[#x](..)`, so it starts with `[`, not the
      // marker. A label's escapes are not undone by the viewport's parser,
      // so an escape here would show as a backslash.
      expect(
        encode('#design #travel', [
          const Entity(0, 7, EntityKind.hashtag('design')),
          const Entity(8, 7, EntityKind.hashtag('travel')),
        ]),
        '[#design](hashtag:design) [#travel](hashtag:travel)',
      );
      expect(
        encode('#tasks', [const Entity(0, 6, EntityKind.hashtag('tasks'))]),
        '[#tasks](hashtag:tasks)',
      );
      expect(
        encode('1. a\n- b', [const Entity(0, 2, EntityKind.link('u'))]),
        '[1.](u) a\n\\- b',
      );
    });

    test('still escapes a marker that a label does not cover', () {
      expect(
        encode('# #tag', [const Entity(2, 4, EntityKind.hashtag('tag'))]),
        r'\# [#tag](hashtag:tag)',
      );
      expect(
        encode('#a', [const Entity(1, 1, EntityKind.link('u'))]),
        r'\#[a](u)',
      );
    });

    test(
      'a label on a later line, in a quote or in an item is covered too',
      () {
        const tag = EntityKind.hashtag('t');

        expect(
          encode('a\n#t', [const Entity(2, 2, tag)]),
          'a\n[#t](hashtag:t)',
        );
        expect(
          encode('#t', [
            const Entity(0, 2, tag),
            const Entity(0, 2, EntityKind.quote),
          ]),
          '> [#t](hashtag:t)',
        );
        expect(
          encode('#t', [
            const Entity(0, 2, tag),
            const Entity(
              0,
              2,
              EntityKind.list(listKind: EntityListKind.bullet),
            ),
          ]),
          '- [#t](hashtag:t)',
        );
      },
    );
  });

  group('styles', () {
    test('writes each style with its marker', () {
      expect(encode('x', [const Entity(0, 1, _bold)]), '**x**');
      expect(encode('x', [const Entity(0, 1, _italic)]), '*x*');
      expect(encode('x', [const Entity(0, 1, EntityKind.underline)]), '__x__');
      expect(encode('x', [const Entity(0, 1, EntityKind.strike)]), '~~x~~');
      expect(encode('x', [const Entity(0, 1, EntityKind.spoiler)]), '||x||');
      expect(encode('x', [const Entity(0, 1, EntityKind.code)]), '`x`');
    });

    test('closes a style where it ends', () {
      expect(
        encode('hello world', [const Entity(0, 5, _bold)]),
        '**hello** world',
      );
    });

    test('nests styles that cover the same span', () {
      expect(
        encode('x', [const Entity(0, 1, _bold), const Entity(0, 1, _italic)]),
        '***x***',
      );
    });

    test('nests a style inside a longer one', () {
      expect(
        encode('abcd', [
          const Entity(0, 4, _bold),
          const Entity(1, 2, _italic),
        ]),
        '**a*bc*d**',
      );
    });

    test('writes styles that overlap partially as plain toggles', () {
      expect(
        encode('abcdef', [
          const Entity(0, 4, _bold),
          const Entity(2, 4, _italic),
        ]),
        '**ab*cd**ef*',
      );
    });

    test('keeps the characters of a surrogate pair inside the style', () {
      expect(
        encode('\u{1F44D}x', [const Entity(0, 3, _bold)]),
        '**\u{1F44D}x**',
      );
    });

    test('escapes text inside a style', () {
      expect(encode('a*b', [const Entity(0, 3, _bold)]), r'**a\*b**');
    });

    test('escapes a ~ or | that would merge with a marker', () {
      expect(encode('~x', [const Entity(1, 1, EntityKind.strike)]), r'\~~~x~~');
    });
  });

  group('code', () {
    test('is written raw, without escapes', () {
      expect(encode('a*b_c', [const Entity(0, 5, EntityKind.code)]), '`a*b_c`');
    });

    test('uses a longer fence than any backtick run inside', () {
      expect(encode('a`b', [const Entity(0, 3, EntityKind.code)]), '``a`b``');
      expect(
        encode('a`b``c', [const Entity(0, 6, EntityKind.code)]),
        '```a`b``c```',
      );
    });

    test('pads content that starts or ends with a backtick or a space', () {
      expect(encode('`a', [const Entity(0, 2, EntityKind.code)]), '`` `a ``');
      expect(encode(' a ', [const Entity(0, 3, EntityKind.code)]), '`  a  `');
      expect(encode(' a', [const Entity(0, 2, EntityKind.code)]), '` a`');
      expect(encode('  ', [const Entity(0, 2, EntityKind.code)]), '`  `');
    });

    test('sits inside other styles', () {
      expect(
        encode('abc', [
          const Entity(0, 3, _bold),
          const Entity(1, 1, EntityKind.code),
        ]),
        '**a`b`c**',
      );
    });
  });

  group('links, mentions and inline content', () {
    test('writes a link', () {
      expect(
        encode('see this', [
          const Entity(4, 4, EntityKind.link('https://a.b/c')),
        ]),
        'see [this](https://a.b/c)',
      );
    });

    test('escapes a link label and quotes awkward targets', () {
      expect(
        encode('a]b', [const Entity(0, 3, EntityKind.link('u'))]),
        r'[a\]b](u)',
      );
      expect(
        encode('t', [const Entity(0, 1, EntityKind.link('https://x/a_(b)'))]),
        r'[t](https://x/a_\(b\))',
      );
      expect(
        encode('t', [const Entity(0, 1, EntityKind.link('https://x/a b'))]),
        '[t](<https://x/a b>)',
      );
    });

    test('cuts a link at style boundaries so the markers stay outside it', () {
      expect(
        encode('abc', [
          const Entity(0, 3, EntityKind.link('u')),
          const Entity(1, 1, _bold),
        ]),
        '[a](u)**[b](u)**[c](u)',
      );
      expect(
        encode('abcd', [
          const Entity(0, 3, EntityKind.link('u')),
          const Entity(1, 3, _bold),
        ]),
        '[a](u)**[bc](u)d**',
      );
    });

    test('writes a mention with the mention scheme', () {
      expect(
        encode('hi @alice!', [const Entity(3, 6, EntityKind.mention('alice'))]),
        'hi [@alice](mention:alice)!',
      );
    });

    test('writes inline content with the encoded content key', () {
      expect(
        encode('a\u{1F44D}b', [
          const Entity(
            1,
            2,
            EntityKind.inlineContent(ContentKey.unicode('\u{1F44D}')),
          ),
        ]),
        'a![\u{1F44D}](unicode:1F44D)b',
      );
      expect(
        encode(':)', [
          const Entity(
            0,
            2,
            EntityKind.inlineContent(ContentKey.document('5368')),
          ),
        ]),
        '![:)](document:5368)',
      );
      expect(
        encode('x', [
          const Entity(
            0,
            1,
            EntityKind.inlineContent(ContentKey.external('a b')),
          ),
        ]),
        '![x](<external:a b>)',
      );
    });

    test('keeps a bang from turning a link into an image', () {
      expect(
        encode('wow!x', [const Entity(4, 1, EntityKind.link('u'))]),
        r'wow\![x](u)',
      );
    });

    test('puts inline content inside a style and a link', () {
      expect(
        encode('a\u{1F44D}', [
          const Entity(0, 3, EntityKind.link('u')),
          const Entity(0, 3, _bold),
          const Entity(
            1,
            2,
            EntityKind.inlineContent(ContentKey.unicode('\u{1F44D}')),
          ),
        ]),
        '**[a](u)[![\u{1F44D}](unicode:1F44D)](u)**',
      );
    });
  });

  group('quotes', () {
    test('prefixes each line of the quote', () {
      expect(
        encode('a\nb\nc', [const Entity(2, 3, EntityKind.quote)]),
        'a\n> b\n> c',
      );
    });

    test('ends the quote with a blank line when text follows', () {
      expect(
        encode('q\nrest', [const Entity(0, 1, EntityKind.quote)]),
        '> q\n\nrest',
      );
    });

    test('writes an empty line inside a quote as a bare marker', () {
      expect(
        encode('a\n\nb', [const Entity(0, 4, EntityKind.quote)]),
        '> a\n>\n> b',
      );
    });

    test('keeps styles inside the quote', () {
      expect(
        encode('ab', [
          const Entity(0, 2, EntityKind.quote),
          const Entity(1, 1, _bold),
        ]),
        '> a**b**',
      );
    });
  });

  group('ADR 017: no auto-detection', () {
    test('a bare URL and a bare @name are written as plain text', () {
      const text =
          'see https://example.com/a_b?x=1 and www.example.com or @alice';

      expect(encode(text), text);
      expect(encode(text), isNot(contains('](')));
      expect(encode(text), isNot(contains('mention:')));
    });
  });
}
