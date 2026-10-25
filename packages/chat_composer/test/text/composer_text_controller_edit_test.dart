import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

void main() {
  late ComposerTextController controller;

  tearDown(() => controller.dispose());

  void start(RichText text, {int? caret}) {
    controller = ComposerTextController(initial: text);
    controller.selection = TextSelection.collapsed(
      offset: caret ?? text.length,
    );
  }

  group('construction', () {
    test('starts empty', () {
      controller = ComposerTextController();

      expect(controller.text, isEmpty);
      expect(controller.richText, RichText.empty);
    });

    test('starts from a rich text and exposes it unchanged', () {
      final initial = RichText('hello world', const [
        Entity(0, 5, EntityKind.bold),
      ]);
      controller = ComposerTextController(initial: initial);

      expect(controller.text, 'hello world');
      expect(controller.richText, initial);
    });
  });

  group('typing', () {
    test('before an entity shifts it', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]), caret: 0);

      controller.type('x ');

      expect(
        controller.richText,
        RichText('x bold', const [Entity(2, 4, EntityKind.bold)]),
      );
    });

    test('inside an entity grows it', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]), caret: 2);

      controller.type('XY');

      expect(
        controller.richText,
        RichText('boXYld', const [Entity(0, 6, EntityKind.bold)]),
      );
    });

    test('at the edge of an entity continues it up to whitespace', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.type('! x');

      expect(
        controller.richText,
        RichText('bold! x', const [Entity(0, 5, EntityKind.bold)]),
      );
    });
  });

  group('deleting and replacing', () {
    test('across the end of an entity keeps the part outside the range', () {
      start(RichText('ab cd ef', const [Entity(3, 2, EntityKind.italic)]));

      controller.deleteRange(4, 7);

      expect(
        controller.richText,
        RichText('ab cf', const [Entity(3, 1, EntityKind.italic)]),
      );
    });

    test('over a whole entity removes it', () {
      start(RichText('a bold b', const [Entity(2, 4, EntityKind.bold)]));

      controller.deleteRange(2, 6);

      expect(controller.richText, RichText('a  b'));
    });

    test('replacing a selection with a paste edits once', () {
      start(RichText('one two', const [Entity(4, 3, EntityKind.bold)]));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );

      controller.type('1');

      expect(
        controller.richText,
        RichText('1 two', const [Entity(2, 3, EntityKind.bold)]),
      );
    });

    test('repeated characters resolve through the caret', () {
      start(RichText('aab', const [Entity(0, 1, EntityKind.bold)]), caret: 0);

      // Forward delete of the first "a": the caret stays at 0.
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 0),
      );

      expect(controller.richText, RichText('ab'));
    });

    test(
      'repeated characters, deleting the second one keeps the first style',
      () {
        start(RichText('aab', const [Entity(0, 1, EntityKind.bold)]), caret: 2);

        controller.deleteRange(1, 2);

        expect(
          controller.richText,
          RichText('ab', const [Entity(0, 1, EntityKind.bold)]),
        );
      },
    );

    test('never cuts a surrogate pair', () {
      start(RichText('a\u{1F600}b', const [Entity(0, 4, EntityKind.bold)]));

      // Both emoji share their high surrogate; only the low one differs.
      controller.value = const TextEditingValue(
        text: 'a\u{1F601}b',
        selection: TextSelection.collapsed(offset: 3),
      );

      expect(
        controller.richText,
        RichText('a\u{1F601}b', const [Entity(0, 4, EntityKind.bold)]),
      );
    });
  });

  group('text setter', () {
    test('is an edit that the entities follow', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.text = 'bold!';

      expect(
        controller.richText,
        RichText('bold!', const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    test('clear drops the entities', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.clear();

      expect(controller.richText, RichText.empty);
    });
  });
}
