import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

const _mention = ComposerQueryKind(id: 'mention', trigger: '@');
const _hashtag = ComposerQueryKind(id: 'hashtag', trigger: '#');
const _command = ComposerQueryKind(
  id: 'command',
  trigger: '/',
  rule: ComposerQueryRule.startOfText,
);
final _emoji = ComposerQueryKind(
  id: 'emoji',
  trigger: ':',
  rule: ComposerQueryRule(
    opensAt: ComposerQueryRule.word.opensAt,
    continues: (codePoint) =>
        (codePoint >= 0x61 && codePoint <= 0x7A) || codePoint == 0x5F,
  ),
);

void main() {
  late ComposerController composer;

  setUp(() {
    composer = ComposerController(
      queryKinds: [_mention, _hashtag, _command, _emoji],
    );
  });
  tearDown(() => composer.dispose());

  ComposerInputQuery? typed(String text, {int? caret}) {
    composer.text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    );
    return composer.query.value;
  }

  group('detection', () {
    test('finds nothing in plain text', () {
      expect(typed('hello world'), isNull);
    });

    test('a bare trigger opens an empty query', () {
      final query = typed('hi @');

      expect(query!.kind, _mention);
      expect(query.text, isEmpty);
      expect(query.range, const TextRange(start: 3, end: 4));
    });

    test('carries the text after the trigger and the range with it', () {
      final query = typed('hi @ali');

      expect(query!.kind, _mention);
      expect(query.text, 'ali');
      expect(query.range, const TextRange(start: 3, end: 7));
    });

    test('follows the caret, not the end of the text', () {
      final query = typed('hi @ali and more', caret: 7);

      expect(query!.text, 'ali');
    });

    test('closes when the caret leaves the token', () {
      typed('hi @ali');

      expect(typed('hi @ali ', caret: 8), isNull);
    });

    test('picks the kind by its trigger', () {
      expect(typed('#fl')!.kind, _hashtag);
      expect(typed('#fl')!.text, 'fl');
    });

    test('the trigger must follow the start of the text or whitespace', () {
      expect(typed('mail@host'), isNull);
      expect(typed('a #tag')!.kind, _hashtag);
    });

    test('a start-of-text rule opens only at the start', () {
      expect(typed('/start')!.kind, _command);
      expect(typed('say /start'), isNull);
    });

    test('a rule decides which characters continue the token', () {
      expect(typed(':smi')!.text, 'smi');
      expect(typed(':smi1'), isNull);
    });

    test('works after a surrogate pair', () {
      expect(typed('\u{1F600} @bo')!.text, 'bo');
    });

    test('works with letters beyond ASCII', () {
      expect(typed('@émilie')!.text, 'émilie');
    });

    test('a range selection has no query', () {
      composer.text.value = const TextEditingValue(
        text: '@ali',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      );

      expect(composer.query.value, isNull);
    });

    test('a token is not read through inline content', () {
      composer.text.restore(
        RichText('@a:b:c', const [
          Entity(2, 3, EntityKind.inlineContent(ContentKey.document('x'))),
        ]),
        selection: const TextSelection.collapsed(offset: 6),
      );

      expect(composer.query.value, isNull);
    });

    test('a token longer than the kind allows is not a query', () {
      final tight = ComposerController(
        queryKinds: [
          const ComposerQueryKind(id: 'tag', trigger: '#', maxLength: 4),
        ],
      );
      addTearDown(tight.dispose);

      tight.text.type('#abcde');
      expect(tight.query.value, isNull);

      tight.text.clear();
      tight.text.type('#abcd');
      expect(tight.query.value!.text, 'abcd');
    });

    test('the first registered kind wins when two would match', () {
      final both = ComposerController(
        queryKinds: [
          const ComposerQueryKind(id: 'first', trigger: '@'),
          const ComposerQueryKind(id: 'second', trigger: '@'),
        ],
      );
      addTearDown(both.dispose);

      both.text.type('@a');

      expect(both.query.value!.kind.id, 'first');
    });

    test('while the input method composes the query follows the text', () {
      composer.text.compose('hi @al', const TextRange(start: 4, end: 6));

      expect(composer.query.value!.text, 'al');
    });
  });

  group('observing', () {
    test('signals when the query changes and not when it does not', () {
      var signals = 0;
      composer.query.addListener(() => signals++);

      composer.text.type('@');
      composer.text.type('a');
      composer.text.type('b');
      composer.text.selection = const TextSelection.collapsed(offset: 3);

      expect(signals, 3);
    });

    test('signals when the query closes', () {
      composer.text.type('@a');
      var signals = 0;
      composer.query.addListener(() => signals++);

      composer.text.type(' ');

      expect(signals, 1);
      expect(composer.query.value, isNull);
    });
  });

  group('registration', () {
    test('a kind registered later is detected from then on', () {
      final fresh = ComposerController();
      addTearDown(fresh.dispose);
      fresh.text.type('@a');
      expect(fresh.query.value, isNull);

      fresh.registerQueryKind(_mention);

      expect(fresh.query.value!.text, 'a');
    });

    test('an unregistered kind stops being detected', () {
      composer.text.type('@a');

      composer.unregisterQueryKind('mention');

      expect(composer.query.value, isNull);
    });

    test('two kinds with one id are refused', () {
      expect(
        () => composer.registerQueryKind(
          const ComposerQueryKind(id: 'mention', trigger: '+'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('caret anchor', () {
    test('is null until the field reports it', () {
      composer.text.type('@a');

      expect(composer.query.value!.caretAnchor, isNull);
    });

    test('reaches the query once reported', () {
      composer.text.type('@a');

      composer.reportCaretAnchor(const Rect.fromLTWH(10, 20, 1, 18));

      expect(
        composer.query.value!.caretAnchor,
        const Rect.fromLTWH(10, 20, 1, 18),
      );
    });

    test('survives edits of the same token', () {
      composer.text.type('@a');
      composer.reportCaretAnchor(const Rect.fromLTWH(10, 20, 1, 18));

      composer.text.type('b');

      expect(composer.query.value!.text, 'ab');
      expect(composer.query.value!.caretAnchor, isNotNull);
    });

    test('is dropped when the query closes', () {
      composer.text.type('@a');
      composer.reportCaretAnchor(const Rect.fromLTWH(10, 20, 1, 18));
      composer.text.type(' ');
      composer.text.type('@');

      expect(composer.query.value!.caretAnchor, isNull);
    });

    test('is ignored when there is no query', () {
      composer.reportCaretAnchor(const Rect.fromLTWH(1, 2, 3, 4));

      expect(composer.query.value, isNull);
    });
  });

  group('replaceQuery', () {
    test(
      'swaps the token for the replacement and moves the caret after it',
      () {
        composer.text.type('hi @al');
        final query = composer.query.value!;

        final replaced = composer.replaceQuery(
          query,
          RichText('@alice ', const [
            Entity(0, 6, EntityKind$Mention('alice')),
          ]),
        );

        expect(replaced, isTrue);
        expect(
          composer.richText,
          RichText('hi @alice ', const [
            Entity(3, 6, EntityKind$Mention('alice')),
          ]),
        );
        expect(
          composer.text.selection,
          const TextSelection.collapsed(offset: 10),
        );
        expect(composer.query.value, isNull);
      },
    );

    test('works for an inline content reply', () {
      composer.text.type(':smi');
      final query = composer.query.value!;
      const smile = InlineContentRef(
        key: ContentKey.document('smile'),
        alternativeText: '\u{1F642}',
      );

      composer.replaceQuery(
        query,
        RichText('\u{1F642}', [
          Entity(0, 2, EntityKind.inlineContent(smile.key)),
        ]),
      );

      expect(composer.text.text, '\u{1F642}');
      expect(
        composer.richText.inlineContentOf(composer.richText.entities.single),
        smile,
      );
    });

    test('refuses a query that no longer matches the text', () {
      composer.text.type('@al');
      final stale = composer.query.value!;
      composer.text.type('i');

      final replaced = composer.replaceQuery(stale, RichText('@alice'));

      expect(replaced, isFalse);
      expect(composer.text.text, '@ali');
    });

    test('accepts a query copy that only differs by its anchor', () {
      composer.text.type('@al');
      final old = composer.query.value!;
      composer.reportCaretAnchor(const Rect.fromLTWH(1, 2, 3, 4));

      expect(composer.replaceQuery(old, RichText('@bo')), isTrue);
    });
  });
}
