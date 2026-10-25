import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

const _smile = InlineContentRef(
  key: ContentKey.document('smile'),
  alternativeText: '\u{1F642}',
);

void main() {
  late ComposerTextController controller;

  setUp(() => controller = ComposerTextController());
  tearDown(() => controller.dispose());

  group('while the input method composes', () {
    setUp(() {
      controller.restore(
        RichText('word', const [Entity(0, 4, EntityKind.bold)]),
      );
    });

    test('the entities wait for the composition to finish', () {
      controller.compose('wor', const TextRange(start: 0, end: 3));
      expect(controller.isComposing, isTrue);

      controller.compose('words', const TextRange(start: 0, end: 5));

      // The pending edit is one insertion at the run's end, which continues
      // the run; what the controller keeps is still the text before it.
      expect(
        controller.richText,
        RichText('words', const [Entity(0, 5, EntityKind.bold)]),
      );

      controller.commitComposition('words');

      expect(controller.isComposing, isFalse);
      expect(
        controller.richText,
        RichText('words', const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    test('richText always describes the text that is shown', () {
      controller.compose('wo', const TextRange(start: 0, end: 2));

      expect(controller.richText.plain, controller.text);

      controller.compose('wonder', const TextRange(start: 0, end: 6));

      expect(controller.richText.plain, controller.text);
    });

    test(
      'a composition that is abandoned leaves the entities as they were',
      () {
        controller.compose('wordx', const TextRange(start: 4, end: 5));

        controller.commitComposition('word');

        expect(
          controller.richText,
          RichText('word', const [Entity(0, 4, EntityKind.bold)]),
        );
      },
    );

    test('one replacement is applied when it finishes', () {
      controller.compose('wo', const TextRange(start: 0, end: 2));
      controller.commitComposition('woürd');

      expect(controller.richText.plain, 'woürd');
      expect(controller.richText.entities.single.kind, EntityKind.bold);
    });

    test('does not move the caret off an inline reference', () {
      controller.restore(RichText.empty);
      controller.insertText('a');
      controller.insertContent(_smile);
      controller.insertText('b');

      controller.compose(
        'a\u{1F642}b',
        const TextRange(start: 3, end: 4),
        caret: 2,
      );

      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    test('a programmatic insert ends the composition', () {
      controller.compose('words', const TextRange(start: 0, end: 5));

      controller.insertText('!');

      expect(controller.isComposing, isFalse);
      expect(controller.richText.plain, 'words!');
    });

    test('clearComposing commits the pending edit', () {
      controller.compose('words', const TextRange(start: 0, end: 5));

      controller.clearComposing();

      expect(controller.isComposing, isFalse);
      expect(
        controller.richText,
        RichText('words', const [Entity(0, 5, EntityKind.bold)]),
      );
    });
  });
}
