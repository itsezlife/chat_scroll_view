/// Usernames and hashtags in markdown: `[@name](username:name)` and
/// `[#tag](hashtag:tag)`.
///
/// **Seam:** `RichTextMarkdown.encode` and `decode`.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

const _alice = EntityKind.username('alice');
const _tag = EntityKind.hashtag('dart');

void expectRoundTrip(RichText text) {
  final markdown = RichTextMarkdown.encode(text);

  expect(
    RichTextMarkdown.decode(markdown),
    text,
    reason: 'through ${markdown.replaceAll('\n', r'\n')}',
  );
}

void main() {
  test('are written as links to their scheme', () {
    final text = RichText('hi @alice and #dart!', const [
      Entity(3, 6, _alice),
      Entity(14, 5, _tag),
    ]);

    expect(
      RichTextMarkdown.encode(text),
      'hi [@alice](username:alice) and [#dart](hashtag:dart)!',
    );
  });

  test('are read from their scheme, and a mention stays a mention', () {
    final text = RichTextMarkdown.decode(
      '[@alice](username:alice) [@bob](mention:bob) [#dart](hashtag:dart)',
    );

    expect(text.plain, '@alice @bob #dart');
    expect(text.entities, const [
      Entity(0, 6, _alice),
      Entity(7, 4, EntityKind.mention('bob')),
      Entity(12, 5, _tag),
    ]);
  });

  test('a scheme with no name is text', () {
    expect(
      RichTextMarkdown.decode('[a](username:) [b](hashtag:)'),
      const RichText.plain('[a](username:) [b](hashtag:)'),
    );
  });

  test('bare @name and #tag stay text (ADR 017)', () {
    expect(
      RichTextMarkdown.decode('@alice #dart'),
      const RichText.plain('@alice #dart'),
    );
  });

  test('round trip next to links and mentions', () {
    expectRoundTrip(
      RichText('@alice @bob #dart link @carol', const [
        Entity(0, 6, _alice),
        Entity(7, 4, EntityKind.mention('bob')),
        Entity(12, 5, _tag),
        Entity(18, 4, EntityKind.link('https://x/a_(b)')),
        Entity(23, 6, EntityKind.username('carol')),
      ]),
    );
    expectRoundTrip(
      RichText('@alice#dart[x]', const [
        Entity(0, 6, _alice),
        Entity(6, 5, _tag),
        Entity(11, 3, EntityKind.link('u')),
      ]),
    );
  });

  test('round trip with styles across and inside the name', () {
    expectRoundTrip(
      RichText('say @alice now', const [
        Entity(4, 6, _alice),
        Entity(0, 7, EntityKind.bold),
        Entity(6, 8, EntityKind.italic),
      ]),
    );
  });

  test(
    'round trip of names that need a destination in brackets or escapes',
    () {
      expectRoundTrip(
        RichText('@a b #c(d)', const [
          Entity(0, 4, EntityKind.username('a b')),
          Entity(5, 5, EntityKind.hashtag('c(d)')),
        ]),
      );
    },
  );

  test(
    'a link cannot be built from the schemes, so decode never makes one',
    () {
      final text = RichTextMarkdown.decode('[x](username:a) [y](hashtag:b)');

      expect(text.entities.map((e) => e.kind), const [
        EntityKind.username('a'),
        EntityKind.hashtag('b'),
      ]);
    },
  );
}
