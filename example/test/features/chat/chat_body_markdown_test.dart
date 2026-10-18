/// The host's conversion between what the composer holds (a `RichText`) and
/// what a message carries (a markdown body), at the two moments a body crosses
/// it: sending, and loading a message back into the composer to edit it.
///
/// The conformance group parses the helper's output with the real `flutter_md`
/// parser the viewport renders with, so a dialect drift between the two shows
/// here and not on a screen.
library;

import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Rich = model.RichText;

const _thumbsUp = '\u{1F44D}';

/// A sticker's reference as another client would send it.
const _party = Entity(
  0,
  5,
  EntityKind.inlineContent(ContentKey.document('5368')),
);

const _family = '\u{1F468}‍\u{1F469}‍\u{1F467}';

ContentKey _emoji(String glyph) => ContentKey.unicode(glyph);

_Rich _withEmoji(String before, String glyph, String after) =>
    _Rich('$before$glyph$after', [
      Entity(
        before.length,
        glyph.length,
        EntityKind.inlineContent(_emoji(glyph)),
      ),
    ]);

/// What the viewport sees of [body]: its paragraph spans as text and styles
/// (`''` for plain text).
List<(String, String)> _spans(String body) => [
  for (final block in Markdown.fromString(body).blocks)
    if (block is MD$Paragraph)
      for (final span in block.spans)
        (span.text, (span.style.styles.toList()..sort()).join('+')),
];

void main() {
  group('sending', () {
    test('a picked emoji travels as its characters', () {
      final body = ChatBodyMarkdown.encode(_withEmoji('hi ', _thumbsUp, '!'));

      expect(body, 'hi $_thumbsUp!');
    });

    test('a sequence of joined emoji stays whole', () {
      final body = ChatBodyMarkdown.encode(_withEmoji('', _family, ''));

      expect(body, _family);
    });

    test(
      'other content keeps its reference, with the alt text as the label',
      () {
        final sticker = _Rich('party', const [_party]);

        expect(ChatBodyMarkdown.encode(sticker), '![party](document:5368)');
      },
    );

    test('formatting is written in the viewport\'s dialect', () {
      final text = _Rich('make it loud', const [Entity(8, 4, EntityKind.bold)]);

      expect(ChatBodyMarkdown.encode(text), 'make it **loud**');
    });

    test('surrounding blanks are not sent', () {
      expect(ChatBodyMarkdown.encode(const _Rich.plain('  hello \n')), 'hello');
    });

    test('encode alone does not detect: that is send\'s step', () {
      const typed = _Rich.plain('see https://example.com and @alice');

      expect(
        ChatBodyMarkdown.encode(typed),
        'see https://example.com and @alice',
      );
    });
  });

  group('send detects, then encodes', () {
    test('a bare URL, @name and #tag go out as links the wire reads back', () {
      const typed = _Rich.plain('see https://example.com @alice #news');

      final body = ChatBodyMarkdown.send(typed);

      expect(
        body,
        'see [https://example.com](https://example.com) '
        '[@alice](username:alice) [#news](hashtag:news)',
      );
      expect(ChatBodyMarkdown.decode(body).entities.map((e) => e.kind), [
        const EntityKind.link('https://example.com'),
        const EntityKind.username('alice'),
        const EntityKind.hashtag('news'),
      ]);
    });

    test('a link the user made is kept, not detected again inside', () {
      final typed = _Rich('docs a.com', const [
        Entity(0, 4, EntityKind.link('https://flutter.dev')),
      ]);

      expect(
        ChatBodyMarkdown.send(typed),
        '[docs](https://flutter.dev) [a.com](https://a.com)',
      );
    });

    test('a mention stays a mention, a name beside it is detected', () {
      final typed = _Rich('@Ann and @bob', const [
        Entity(0, 4, EntityKind.mention('7')),
      ]);

      expect(
        ChatBodyMarkdown.send(typed),
        '[@Ann](mention:7) and [@bob](username:bob)',
      );
    });
  });

  group('receive is a fallback for a body with no entity', () {
    test('a stored bare URL shows a link', () {
      final body = ChatBodyMarkdown.received('see https://example.com now');

      expect(
        ChatBodyMarkdown.decode(body).entities.single.kind,
        const EntityKind.link('https://example.com'),
      );
    });

    test('a body with a link is trusted: a second bare URL stays text', () {
      const stored = '[docs](https://flutter.dev) and https://example.com';

      final body = ChatBodyMarkdown.received(stored);

      expect(body, stored);
      expect(ChatBodyMarkdown.decode(body).entities, hasLength(1));
    });

    test('a mention, a username or a hashtag also trusts the body', () {
      for (final stored in [
        '[@Ann](mention:7) https://example.com',
        '[@bob](username:bob) https://example.com',
        '[#dart](hashtag:dart) https://example.com',
      ]) {
        expect(ChatBodyMarkdown.received(stored), stored, reason: stored);
      }
    });

    test('a body with a style only is still detected', () {
      final body = ChatBodyMarkdown.received('**loud** a.com');

      expect(
        ChatBodyMarkdown.decode(body).entities.map((e) => e.kind),
        containsAll([EntityKind.bold, const EntityKind.link('https://a.com')]),
      );
    });

    test('a body with nothing to detect comes back as it was stored', () {
      const stored = 'plain *text*, nothing to link';

      expect(ChatBodyMarkdown.received(stored), stored);
    });

    test('the detector runs once for a body and never for a trusted one', () {
      final before = ChatBodyMarkdown.detectionRuns;

      ChatBodyMarkdown.received('see https://example.com');
      expect(ChatBodyMarkdown.detectionRuns, before + 1);

      ChatBodyMarkdown.received('[a](https://a.com) https://b.com');
      expect(ChatBodyMarkdown.detectionRuns, before + 1);
    });
  });

  group('edit-load strips what detection made and send makes it again', () {
    test('a stored link to its own URL loads as a link, edits as text', () {
      const stored = 'go [https://example.com](https://example.com)';

      expect(
        ChatBodyMarkdown.decode(stored).entities.single.kind,
        const EntityKind.link('https://example.com'),
      );
      final editable = ChatBodyMarkdown.decodeForEdit(stored);
      expect(editable.plain, 'go https://example.com');
      expect(editable.entities, isEmpty);
      expect(ChatBodyMarkdown.send(editable), stored);
    });

    test('a username and a hashtag edit as text and come back on save', () {
      const stored = '[@alice](username:alice) [#news](hashtag:news)';

      final editable = ChatBodyMarkdown.decodeForEdit(stored);

      expect(editable.plain, '@alice #news');
      expect(editable.entities, isEmpty);
      expect(ChatBodyMarkdown.send(editable), stored);
    });

    test('an explicit link, a mention and the styles stay', () {
      const stored =
          '**[docs](https://flutter.dev)** and [@Ann](mention:7) a.com';

      final editable = ChatBodyMarkdown.decodeForEdit(stored);

      expect(editable.plain, 'docs and @Ann a.com');
      expect(
        editable.entities.map((e) => e.kind),
        unorderedEquals([
          EntityKind.bold,
          const EntityKind.link('https://flutter.dev'),
          const EntityKind.mention('7'),
        ]),
      );
    });
  });

  group('editing', () {
    test('a body loads back with its formatting as entities', () {
      final text = ChatBodyMarkdown.decode('make it **loud** $_thumbsUp');

      expect(text.plain, 'make it loud $_thumbsUp');
      expect(text.entities, const [Entity(8, 4, EntityKind.bold)]);
    });

    test('an emoji sent as characters comes back as characters', () {
      final sent = ChatBodyMarkdown.encode(_withEmoji('a', _thumbsUp, 'b'));

      final back = ChatBodyMarkdown.decode(sent);

      expect(back.plain, 'a${_thumbsUp}b');
      expect(back.entities, isEmpty);
    });

    test('an inline reference written by another client loads as one', () {
      final text = ChatBodyMarkdown.decode(
        'x ![$_thumbsUp](${_emoji(_thumbsUp).encoded}) y',
      );

      expect(text.plain, 'x $_thumbsUp y');
      expect(
        text.entities.single.kind,
        EntityKind.inlineContent(_emoji(_thumbsUp)),
      );
      expect(text.textOf(text.entities.single), _thumbsUp);
    });

    test('a mention loads as an atomic entity', () {
      final text = ChatBodyMarkdown.decode('hi [@alice](mention:alice)');

      expect(text.entities, const [Entity(3, 6, EntityKind.mention('alice'))]);
    });
  });

  group('conformance with the viewport\'s markdown parser', () {
    test('every style the composer can write reads back as that style', () {
      final cases = <(_Rich, List<(String, String)>)>[
        (
          _Rich('a bold b', const [Entity(2, 4, EntityKind.bold)]),
          [('a ', ''), ('bold', 'bold'), (' b', '')],
        ),
        (
          _Rich('an italic', const [Entity(3, 6, EntityKind.italic)]),
          [('an ', ''), ('italic', 'italic')],
        ),
        (
          _Rich('x gone', const [Entity(2, 4, EntityKind.strike)]),
          [('x ', ''), ('gone', 'strikethrough')],
        ),
        (
          _Rich('c code d', const [Entity(2, 4, EntityKind.code)]),
          [('c ', ''), ('code', 'monospace'), (' d', '')],
        ),
        (
          _Rich('go there', const [
            Entity(0, 2, EntityKind.link('https://a.b')),
          ]),
          [('go', 'link'), (' there', '')],
        ),
        (
          _Rich('hi @alice', const [Entity(3, 6, EntityKind.mention('alice'))]),
          [('hi ', ''), ('@alice', 'link')],
        ),
      ];

      for (final (text, expected) in cases) {
        expect(
          _spans(ChatBodyMarkdown.encode(text)),
          expected,
          reason: text.plain,
        );
      }
    });

    test('a link carries its target and a mention its scheme', () {
      final body = ChatBodyMarkdown.encode(
        _Rich('hi @alice and site', const [
          Entity(3, 6, EntityKind.mention('alice')),
          Entity(14, 4, EntityKind.link('https://a.b/c')),
        ]),
      );

      final spans = [
        for (final block in Markdown.fromString(body).blocks)
          if (block is MD$Paragraph) ...block.spans,
      ];
      final links = {
        for (final span in spans)
          if (span.style.contains(MD$Style.link))
            span.text: span.extra!['href'],
      };

      expect(links, {'@alice': 'mention:alice', 'site': 'https://a.b/c'});
    });

    test('a reference to other content reads as one image span with its '
        'target', () {
      final body = ChatBodyMarkdown.encode(_Rich('party', const [_party]));

      final span = Markdown.fromString(
        body,
      ).blocks.whereType<MD$Paragraph>().single.spans.single;

      expect(span.text, 'party');
      expect(span.style.styles, {'image'});
      expect(span.extra!['src'], 'document:5368');
    });

    test('text that looks like markup is shown as typed', () {
      const typed = _Rich.plain('2 * 3 * 4 and `tick` and [not](a link)');

      final spans = _spans(ChatBodyMarkdown.encode(typed));

      expect(spans.map((span) => span.$1).join(), typed.plain);
      expect(spans.every((span) => span.$2.isEmpty), isTrue);
    });
  });
}
