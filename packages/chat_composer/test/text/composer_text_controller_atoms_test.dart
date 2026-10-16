import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

const _smile = InlineContentRef(
  key: ContentKey.document('smile'),
  alternativeText: '\u{1F642}',
);
const _wide = InlineContentRef(
  key: ContentKey.document('wide'),
  alternativeText: ':wide:',
);

void main() {
  late ComposerTextController controller;

  setUp(() => controller = ComposerTextController());
  tearDown(() => controller.dispose());

  group('insertContent', () {
    test('writes the alternative text under an atomic entity', () {
      controller.insertText('hi ');

      controller.insertContent(_smile);

      expect(controller.text, 'hi \u{1F642}');
      expect(
        controller.richText,
        RichText('hi \u{1F642}', [
          Entity(3, 2, EntityKind.inlineContent(_smile.key)),
        ]),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    });

    test('replaces the selection', () {
      controller.insertText('abcd');
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );

      controller.insertContent(_smile);

      expect(controller.text, 'a\u{1F642}d');
    });

    test('inside code keeps the text and drops the entity', () {
      controller.restore(
        RichText('code', const [Entity(0, 4, EntityKind.code)]),
        selection: const TextSelection.collapsed(offset: 2),
      );

      controller.insertContent(_smile);

      expect(
        controller.richText,
        RichText('co\u{1F642}de', const [Entity(0, 6, EntityKind.code)]),
      );
    });

    test('hands the reference back through the rich text', () {
      controller.insertContent(_wide);

      final entity = controller.richText.entities.single;
      expect(controller.richText.inlineContentOf(entity), _wide);
    });
  });

  group('backspace over inline content', () {
    setUp(() {
      controller
        ..insertText('a')
        ..insertContent(_wide)
        ..insertText('b');
    });

    test('removes the whole reference, not one character of it', () {
      controller.selection = const TextSelection.collapsed(offset: 7);

      controller.deleteBackward();

      expect(controller.text, 'ab');
      expect(controller.richText.entities, isEmpty);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
    });

    test('a platform delete of one character removes the whole reference', () {
      controller.selection = const TextSelection.collapsed(offset: 7);

      controller.deleteRange(6, 7);

      expect(controller.text, 'ab');
      expect(controller.richText.entities, isEmpty);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
    });

    test('removes one grapheme cluster elsewhere', () {
      // "e" with a combining acute accent, then "x".
      controller.restore(RichText('e\u0301x'));

      controller.deleteBackward();
      expect(controller.text, 'e\u0301');

      controller.deleteBackward();
      expect(controller.text, isEmpty);
    });

    test('at the start does nothing', () {
      controller.selection = const TextSelection.collapsed(offset: 0);

      controller.deleteBackward();

      expect(controller.text, 'a:wide:b');
    });

    test('deletes a range selection that cuts into the reference', () {
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );

      controller.deleteBackward();

      expect(controller.text, 'b');
      expect(controller.richText.entities, isEmpty);
    });
  });

  group('selection around inline content', () {
    setUp(() {
      controller
        ..insertText('a')
        ..insertContent(_wide)
        ..insertText('b');
    });

    test('a caret moving forward into it lands after it', () {
      controller.selection = const TextSelection.collapsed(offset: 1);

      controller.selection = const TextSelection.collapsed(offset: 2);

      expect(controller.selection, const TextSelection.collapsed(offset: 7));
    });

    test('a caret moving back into it lands before it', () {
      controller.selection = const TextSelection.collapsed(offset: 7);

      controller.selection = const TextSelection.collapsed(offset: 6);

      expect(controller.selection, const TextSelection.collapsed(offset: 1));
    });

    test('a range selection widens to hold it whole', () {
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
    });
  });

  group('mentions', () {
    test('are atomic too', () {
      controller.restore(
        RichText('hi @al', const [Entity(3, 3, EntityKind$Mention('al'))]),
      );

      controller.deleteBackward();

      expect(controller.richText, RichText('hi '));
    });
  });
}
