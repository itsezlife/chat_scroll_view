/// The host's conversion between what the composer holds (a `RichText`) and
/// what a message carries (a markdown body), at the two moments a body crosses
/// it: sending, and loading a message back into the composer to edit it.
///
/// The conformance group is the seam between the two repositories: what
/// `RichTextMarkdown` writes, the pinned `flutter_md` parser the viewport
/// renders with reads back as the entity it came from. The fork pins each
/// spelling in its own suite; this group holds no list of spans of its own, so
/// a drift shows here and not on a screen.
library;

import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/markdown.dart';
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

/// The span style a kind must read back as, or null for a kind that is not an
/// inline span (a quote, a code block, a list item).
MD$Style? _styleOf(EntityKind kind) => switch (kind) {
  EntityKind$Style(:final style) => switch (style) {
    EntityStyle.bold => MD$Style.bold,
    EntityStyle.italic => MD$Style.italic,
    EntityStyle.underline => MD$Style.underline,
    EntityStyle.strike => MD$Style.strikethrough,
    EntityStyle.spoiler => MD$Style.spoiler,
    EntityStyle.code => MD$Style.monospace,
    EntityStyle.quote => null,
  },
  EntityKind$Link() => MD$Style.link,
  EntityKind$Mention() ||
  EntityKind$Username() ||
  EntityKind$Hashtag() => MD$Style.mention,
  EntityKind$InlineContent() => MD$Style.image,
  EntityKind$CodeBlock() || EntityKind$List() => null,
};

/// The `extra` entries a kind's span must carry.
Map<String, Object?> _extraOf(EntityKind kind) => switch (kind) {
  EntityKind$Link(:final url) => {'href': url},
  EntityKind$Mention(:final id) => {'scheme': 'mention', 'id': id},
  EntityKind$Username(:final name) => {'scheme': 'username', 'name': name},
  EntityKind$Hashtag(:final tag) => {'scheme': 'hashtag', 'name': tag},
  EntityKind$InlineContent(:final key) => {'src': key.encoded},
  _ => const {},
};

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

  group('an emoji-only draft is sent as typed', () {
    // Telegram Android skips the trim for it (research 05 section 3.6), so a
    // multi-line arrangement of emoji survives.
    test('its blank lines and trailing space are not trimmed', () {
      expect(
        ChatBodyMarkdown.send(const _Rich.plain('$_thumbsUp\n\n$_thumbsUp ')),
        '$_thumbsUp\n\n$_thumbsUp ',
      );
    });

    test('also when the picker made the emoji entities', () {
      final picked = _withEmoji('', _thumbsUp, ' ');

      expect(ChatBodyMarkdown.send(picked), '$_thumbsUp ');
    });

    test('a custom emoji is emoji, too', () {
      final text = _Rich('\n\u{1F680} ', const [
        Entity(1, 2, EntityKind.inlineContent(ContentKey.document('rocket'))),
      ]);

      expect(ChatBodyMarkdown.send(text), '\n![\u{1F680}](document:rocket) ');
    });

    test('any other text is trimmed as before', () {
      expect(ChatBodyMarkdown.send(const _Rich.plain(' hi ')), 'hi');
      expect(
        ChatBodyMarkdown.send(const _Rich.plain(' $_thumbsUp hi ')),
        '$_thumbsUp hi',
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

    test('a stored body that begins with a bare #tag shows a hashtag', () {
      expect(
        ChatBodyMarkdown.received('#design #travel'),
        '[#design](hashtag:design) [#travel](hashtag:travel)',
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
    // The fork pins how each spelling parses (its dialect conformance suite).
    // This group pins only the seam between the two repositories: what
    // RichTextMarkdown writes, the viewport's parser reads back as the entity
    // it came from. The expectation is computed from each entity, so there is
    // no second list of spans to keep in step with the fork's.
    final corpus = <_Rich>[
      _Rich('bold italic under strike spoil code', const [
        Entity(0, 4, EntityKind.bold),
        Entity(5, 6, EntityKind.italic),
        Entity(12, 5, EntityKind.underline),
        Entity(18, 6, EntityKind.strike),
        Entity(25, 5, EntityKind.spoiler),
        Entity(31, 4, EntityKind.code),
      ]),
      _Rich('go @alice @bob #tag party x', const [
        Entity(0, 2, EntityKind.link('https://a.b/c?d=1')),
        Entity(3, 6, EntityKind.mention('alice')),
        Entity(10, 4, EntityKind.username('bob')),
        Entity(15, 4, EntityKind.hashtag('tag')),
        Entity(20, 5, EntityKind.inlineContent(ContentKey.document('5368'))),
      ]),
      // A label first on the line: the writer must not escape a block marker
      // there, because the parser keeps the backslashes of a label.
      _Rich('#design #travel', const [
        Entity(0, 7, EntityKind.hashtag('design')),
        Entity(8, 7, EntityKind.hashtag('travel')),
      ]),
      _Rich('#tasks', const [Entity(0, 6, EntityKind.hashtag('tasks'))]),
      _Rich('@user hi', const [Entity(0, 5, EntityKind.username('user'))]),
      _Rich('1. x', const [Entity(0, 2, EntityKind.link('https://a.b'))]),
      _Rich('> x', const [Entity(0, 1, EntityKind.link('https://a.b'))]),
      _Rich('#a', const [
        Entity(0, 2, EntityKind.hashtag('a')),
        Entity(0, 2, EntityKind.bold),
      ]),
      // Styles that overlap partially and a style around a link.
      _Rich('a bold and italic b', const [
        Entity(2, 8, EntityKind.bold),
        Entity(7, 8, EntityKind.italic),
      ]),
      _Rich('see this one', const [
        Entity(0, 12, EntityKind.bold),
        Entity(4, 4, EntityKind.link('https://a.b')),
      ]),
    ];

    for (final text in corpus) {
      test(text.plain, () {
        final blocks = Markdown.fromString(
          RichTextMarkdown.encode(text),
        ).blocks;
        final spans = [
          for (final block in blocks)
            if (block is MD$Paragraph) ...block.spans,
        ];

        expect(spans.map((span) => span.text).join(), text.plain);

        // Visible offset of each span: the text before it.
        var at = 0;
        final starts = <MD$Span, int>{};
        for (final span in spans) {
          starts[span] = at;
          at += span.text.length;
        }
        for (final entity in text.entities) {
          final style = _styleOf(entity.kind)!;
          final covered = spans.where(
            (span) =>
                starts[span]! < entity.end &&
                starts[span]! + span.text.length > entity.offset,
          );

          expect(covered, isNotEmpty, reason: '$entity');
          for (final span in covered) {
            expect(span.style.contains(style), isTrue, reason: '$entity');
            // A mention-class span is never also a link.
            if (style == MD$Style.mention) {
              expect(span.style.contains(MD$Style.link), isFalse);
            }
            for (final MapEntry(:key, :value) in _extraOf(
              entity.kind,
            ).entries) {
              expect(span.extra?[key], value, reason: '$entity');
            }
          }
        }
      });
    }

    test('block markers typed as plain text are shown as typed', () {
      for (final typed in ['# x', '#x', '- x', '+ x', '> x', '1. x', '2) x']) {
        final spans = Markdown.fromString(
          RichTextMarkdown.encode(_Rich.plain(typed)),
        ).blocks.whereType<MD$Paragraph>().single.spans;

        expect(spans.map((span) => span.text).join(), typed, reason: typed);
      }
    });

    test('text that looks like markup is shown as typed', () {
      const typed = _Rich.plain('2 * 3 * 4 and `tick` and [not](a link)');

      final spans = Markdown.fromString(
        RichTextMarkdown.encode(typed),
      ).blocks.whereType<MD$Paragraph>().single.spans;

      expect(spans.map((span) => span.text).join(), typed.plain);
      expect(spans.every((span) => span.style == MD$Style.none), isTrue);
    });
  });
}
