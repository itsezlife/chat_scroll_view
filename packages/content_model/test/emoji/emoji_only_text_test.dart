/// `EmojiOnlyText.of`: Telegram Android's emoji-only rule over `RichText`.
///
/// **Seam:** `EmojiOnlyText.of` and the `EmojiOnly` it returns.
library;

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

const _thumbs = '\u{1F44D}';
const _family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
const _toned = '\u{1F44D}\u{1F3FD}';
const _keyOne = '1️⃣';
const _keyHash = '#⃣';
const _flag = '\u{1F1FA}\u{1F1E6}';
const _scotland =
    '\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}';
const _heart = '❤️';
const _copyright = '©️';

EmojiOnly? _of(String text, [List<Entity> entities = const []]) =>
    EmojiOnlyText.of(RichText(text, entities));

/// The unicode sequence of each item, failing on a document item.
List<String> _sequences(EmojiOnly? emojiOnly) => [
  for (final item in emojiOnly!.items)
    (item.key as ContentKey$Unicode).sequence,
];

List<int> _breaks(EmojiOnly? emojiOnly) => [
  for (final item in emojiOnly!.items) item.lineBreaksBefore,
];

void main() {
  group('one sequence is one item', () {
    for (final (name, sequence) in const [
      ('a surrogate-pair emoji', _thumbs),
      ('a ZWJ family', _family),
      ('a skin tone', _toned),
      ('a keycap with a variation selector', _keyOne),
      ('a keycap without one', _keyHash),
      ('a flag', _flag),
      ('a subdivision flag (tag sequence)', _scotland),
      ('a BMP emoji with a variation selector', _heart),
      ('a BMP emoji without one', '❤'),
      ('a copyright sign with a variation selector', _copyright),
      ('a registered sign', '®'),
      ('a gender sign after an emoji', '\u{1F937}♀'),
      ('a gender sign after a ZWJ', '\u{1F937}‍♀️'),
      ('a toned person with a ZWJ profession', '\u{1F9D1}\u{1F3FB}‍⚕'),
    ]) {
      test(name, () {
        final result = _of(sequence);

        expect(_sequences(result), [sequence]);
      });
    }

    test('keeps the exact text as the unicode key', () {
      expect(_of(_heart)!.items.single.key, const ContentKey.unicode(_heart));
    });
  });

  group('whitespace and line breaks', () {
    test('two emoji with a space are two items', () {
      final result = _of('$_thumbs $_thumbs');

      expect(_sequences(result), [_thumbs, _thumbs]);
      expect(_breaks(result), [0, 0]);
    });

    test('a line break between emoji is recorded on the second', () {
      final result = _of('$_thumbs\n$_thumbs');

      expect(_sequences(result), [_thumbs, _thumbs]);
      expect(_breaks(result), [0, 1]);
    });

    test('blank lines are counted', () {
      expect(_breaks(_of('$_thumbs\n \n\t$_thumbs')), [0, 2]);
    });

    test('no break runs the emoji together', () {
      expect(_breaks(_of('$_thumbs$_thumbs')), [0, 0]);
    });

    test('leading and trailing spaces, tabs and breaks are dropped', () {
      final result = _of(' \t\n$_thumbs \t\n');

      expect(_sequences(result), [_thumbs]);
      expect(_breaks(result), [0]);
    });

    test('a stray variation selector between emoji is skipped', () {
      expect(_sequences(_of('$_thumbs ️ $_thumbs')), [_thumbs, _thumbs]);
    });

    test('a break after an item ends its sequence', () {
      expect(_sequences(_of('\u{1F937}\n♀')), ['\u{1F937}', '♀']);
    });
  });

  group('disqualifying text', () {
    for (final (name, text) in const [
      ('empty text', ''),
      ('only whitespace', ' \n\t '),
      ('a lone variation selector', '️'),
      ('a lone ZWJ', '‍'),
      ('a lone regional indicator', '\u{1F1FA}'),
      ('a flag and a lone regional indicator', '$_flag\u{1F1FA}'),
      ('a dangling ZWJ at the end', '$_thumbs‍'),
      ('a ZWJ followed by a space', '$_thumbs‍ $_thumbs'),
      ('a ZWJ followed by a letter', '$_thumbs‍a'),
      ('a keycap base with no enclosing mark', '1'),
      ('a digit outside a keycap', '${_thumbs}1'),
      ('a keycap mark with no base', '⃣'),
      ('a letter', 'a'),
      ('a letter between emoji', '${_thumbs}a$_thumbs'),
      ('a no-break space', '$_thumbs $_thumbs'),
      ('a carriage return', '$_thumbs\r$_thumbs'),
      ('an ideographic space', '$_thumbs　$_thumbs'),
      ('a BMP symbol that is not an emoji', '☃☂§'),
      ('punctuation', '$_thumbs!'),
      ('an unpaired surrogate', '\uD83D'),
    ]) {
      test('$name is not emoji-only', () {
        expect(_of(text), isNull);
      });
    }

    test('a non-emoji BMP symbol in the emoji range is not an emoji', () {
      // U+2604 (comet) is an emoji and U+2605 (black star) is not, though both
      // sit in the range Android looks at.
      expect(_of('★'), isNull);
    });
  });

  group('count', () {
    test('has no cap: 200 emoji qualify', () {
      final result = _of(List.filled(200, _thumbs).join());

      expect(result!.items, hasLength(200));
    });

    test('200 emoji separated by spaces and breaks qualify', () {
      final result = _of(List.filled(200, _thumbs).join(' \n'));

      expect(result!.items, hasLength(200));
      expect(_breaks(result).skip(1), everyElement(1));
    });
  });

  group('entities', () {
    const customKey = ContentKey.document('5368');
    const custom = EntityKind.inlineContent(customKey);

    test('one inline document is one document item', () {
      final result = _of(_thumbs, const [Entity(0, 2, custom)]);

      expect(result!.items.single.key, customKey);
    });

    test('a custom emoji keeps the text under it, the others have none', () {
      const text = '$_thumbs$_heart$_thumbs';
      final result = _of(text, const [Entity(2, 2, custom)]);

      expect(result!.items.map((item) => item.alt), ['', _heart, '']);
    });

    test('mixed custom and unicode emoji keep their order', () {
      const text = '$_thumbs$_heart$_thumbs';
      final result = _of(text, const [Entity(2, 2, custom)]);

      expect(result!.items.map((item) => item.key), [
        const ContentKey.unicode(_thumbs),
        customKey,
        const ContentKey.unicode(_thumbs),
      ]);
    });

    test('two custom emoji with a break between record it', () {
      const other = ContentKey.document('9');
      final result = _of('$_thumbs\n$_thumbs', const [
        Entity(0, 2, custom),
        Entity(3, 2, EntityKind.inlineContent(other)),
      ]);

      expect(result!.items.map((item) => item.key), [customKey, other]);
      expect(_breaks(result), [0, 1]);
    });

    test('the text under an inline document is not inspected', () {
      expect(
        _of('a', const [Entity(0, 1, custom)])!.items.single.key,
        customKey,
      );
    });

    test('a sequence cannot run into an inline document', () {
      expect(_of('$_thumbs‍$_thumbs', const [Entity(3, 2, custom)]), isNull);
    });

    test('an inline document that stands for nothing else is emoji-only', () {
      final result = _of('$_thumbs $_thumbs', const [
        Entity(0, 2, custom),
        Entity(3, 2, custom),
      ]);

      expect(result!.items, hasLength(2));
    });

    for (final (name, kind) in const [
      ('bold', EntityKind.bold),
      ('italic', EntityKind.italic),
      ('underline', EntityKind.underline),
      ('strike', EntityKind.strike),
      ('spoiler', EntityKind.spoiler),
      ('code', EntityKind.code),
      ('quote', EntityKind.quote),
      ('a link', EntityKind.link('https://example.com')),
      ('a mention', EntityKind.mention('42')),
      ('a username', EntityKind.username('alice')),
      ('a hashtag', EntityKind.hashtag('dart')),
      ('a code block', EntityKind.codeBlock()),
      ('a list item', EntityKind.list(listKind: EntityListKind.bullet)),
    ]) {
      test('$name over an emoji disqualifies', () {
        expect(_of(_thumbs, [Entity(0, 2, kind)]), isNull);
      });
    }

    test('a disqualifying entity beside a custom emoji disqualifies', () {
      expect(
        _of('$_thumbs $_thumbs', const [
          Entity(0, 2, custom),
          Entity(3, 2, EntityKind.bold),
        ]),
        isNull,
      );
    });

    for (final (name, key) in const [
      ('a unicode key', ContentKey.unicode(_thumbs)),
      ('an external key', ContentKey.external('https://host/a')),
    ]) {
      test('inline content with $name disqualifies', () {
        expect(
          _of(_thumbs, [Entity(0, 2, EntityKind.inlineContent(key))]),
          isNull,
        );
      });
    }
  });

  group('the value', () {
    test('compares by items', () {
      expect(_of('$_thumbs\n$_heart'), _of('$_thumbs\n$_heart'));
      expect(_of('$_thumbs\n$_heart'), isNot(_of('$_thumbs $_heart')));
      expect(
        _of('$_thumbs\n$_heart').hashCode,
        _of('$_thumbs\n$_heart').hashCode,
      );
    });

    test('items are unmodifiable', () {
      final items = _of(_thumbs)!.items;

      expect(
        () => items.add(const EmojiOnlyItem(ContentKey.unicode(_thumbs))),
        throwsUnsupportedError,
      );
    });
  });

  group('EmojiRuns.of: the emoji a text draws in colour', () {
    // The runs as the text they cover, so a test reads as the text does.
    List<String> runs(String text) => [
      for (final (:start, :end) in EmojiRuns.of(text))
        text.substring(start, end),
    ];

    test('finds each sequence among text, with its offsets', () {
      const text = 'ab $_thumbs cd $_flag!';

      expect(EmojiRuns.of(text), [(start: 3, end: 5), (start: 9, end: 13)]);
    });

    for (final (name, sequence) in const [
      ('a surrogate-pair emoji', _thumbs),
      ('a skin tone', _toned),
      ('a ZWJ family', _family),
      ('a flag', _flag),
      ('a subdivision flag', _scotland),
      ('a keycap', _keyOne),
      ('a keycap without a variation selector', _keyHash),
      ('a BMP emoji with a variation selector', _heart),
      ('a copyright sign with a variation selector', _copyright),
      ('an emoji that is drawn in colour by default', '⭐'),
      ('a gender sign after a ZWJ', '\u{1F937}‍♀️'),
    ]) {
      test('$name is one run', () {
        expect(runs('a${sequence}b'), [sequence]);
      });
    }

    test('adjacent emoji are runs of their own', () {
      expect(runs('$_thumbs$_toned$_flag$_flag'), [
        _thumbs,
        _toned,
        _flag,
        _flag,
      ]);
    });

    for (final (name, text) in const [
      ('a heart without a presentation selector', 'a❤b'),
      ('a copyright sign', 'a©b'),
      ('a registered sign', 'a®b'),
      ('a trade mark', 'a™b'),
      ('a digit', 'a1b'),
      ('a hash', 'a#b'),
      ('a digit with a presentation selector but no keycap mark', 'a1\uFE0Fb'),
      ('a hash with a presentation selector but no keycap mark', 'a#\uFE0Fb'),
      ('a star that is not an emoji', 'a★b'),
      ('a stray presentation selector', 'a\uFE0Fb'),
      ('a lone ZWJ', 'a\u200Db'),
      ('a lone regional indicator', 'a\u{1F1FA}b'),
      ('text alone', 'hello, world'),
      ('nothing', ''),
    ]) {
      test('$name is no run: a text glyph stays at the font size', () {
        expect(EmojiRuns.of(text), isEmpty);
      });
    }

    test('a run does not reach across a line break or a space', () {
      expect(runs('$_thumbs\n$_thumbs $_thumbs'), [_thumbs, _thumbs, _thumbs]);
    });
  });
}
