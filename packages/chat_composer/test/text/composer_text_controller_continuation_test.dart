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

  group('typing at the end of a run', () {
    test('continues it', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.type('e');
      controller.type('r');

      expect(
        controller.richText,
        RichText('bolder', const [Entity(0, 6, EntityKind.bold)]),
      );
    });

    test('stops at whitespace, so the next word is plain', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.type(' ');
      controller.type('x');

      expect(
        controller.richText,
        RichText('bold x', const [Entity(0, 4, EntityKind.bold)]),
      );
    });

    test('continues an inserted text only up to its first whitespace', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.type('er and more');

      expect(
        controller.richText,
        RichText('bolder and more', const [Entity(0, 6, EntityKind.bold)]),
      );
    });

    test('continues every run that ends there', () {
      start(
        RichText('ab', const [
          Entity(0, 2, EntityKind.bold),
          Entity(1, 1, EntityKind.italic),
        ]),
      );

      controller.type('c');

      expect(
        controller.richText,
        RichText('abc', const [
          Entity(0, 3, EntityKind.bold),
          Entity(1, 2, EntityKind.italic),
        ]),
      );
    });

    for (final kind in const [
      EntityKind.italic,
      EntityKind.underline,
      EntityKind.strike,
      EntityKind.spoiler,
      EntityKind.code,
      EntityKind.link('https://example.com'),
    ]) {
      test('continues $kind', () {
        start(RichText('ab', [Entity(0, 2, kind)]));

        controller.type('c');

        expect(controller.richText, RichText('abc', [Entity(0, 3, kind)]));
      });
    }
  });

  group('typing at the start of a run', () {
    test('continues it backwards when no run ends there', () {
      start(
        RichText('a bold', const [Entity(2, 4, EntityKind.bold)]),
        caret: 2,
      );

      controller.type('x');

      expect(
        controller.richText,
        RichText('a xbold', const [Entity(2, 5, EntityKind.bold)]),
      );
    });

    test('takes only the inserted text after its last whitespace', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]), caret: 0);

      controller.type('so very ');
      controller.type('x');

      expect(
        controller.richText,
        RichText('so very xbold', const [Entity(8, 5, EntityKind.bold)]),
      );
    });

    test('loses to a run that ends there', () {
      start(
        RichText('ab', const [
          Entity(0, 1, EntityKind.bold),
          Entity(1, 1, EntityKind.italic),
        ]),
        caret: 1,
      );

      controller.type('x');

      expect(
        controller.richText,
        RichText('axb', const [
          Entity(0, 2, EntityKind.bold),
          Entity(2, 1, EntityKind.italic),
        ]),
      );
    });
  });

  group('does not continue', () {
    test('a quote past its line', () {
      start(RichText('quoted', const [Entity(0, 6, EntityKind.quote)]));

      controller.type('\nx');

      expect(
        controller.richText,
        RichText('quoted\nx', const [Entity(0, 6, EntityKind.quote)]),
      );
    });

    test('a mention, which is an atom', () {
      start(RichText('@ann', const [Entity(0, 4, EntityKind.mention('1'))]));

      controller.type('x');

      expect(
        controller.richText,
        RichText('@annx', const [Entity(0, 4, EntityKind.mention('1'))]),
      );
    });

    test('a detected username', () {
      start(RichText('@ann', const [Entity(0, 4, EntityKind.username('ann'))]));

      controller.type('x');

      expect(
        controller.richText,
        RichText('@annx', const [Entity(0, 4, EntityKind.username('ann'))]),
      );
    });

    test('into a command insert, which goes in as given', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.insertText('x');

      expect(
        controller.richText,
        RichText('boldx', const [Entity(0, 4, EntityKind.bold)]),
      );
    });
  });

  group('replacing a selection', () {
    test('continues the run the replaced range ended against', () {
      start(RichText('bold one', const [Entity(0, 4, EntityKind.bold)]));
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );

      controller.type('x');

      expect(
        controller.richText,
        RichText('box', const [Entity(0, 3, EntityKind.bold)]),
      );
    });
  });

  group('an IME composition', () {
    test('shows the continued run while it composes and keeps it', () {
      start(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));

      controller.compose('bolder', const TextRange(start: 4, end: 6));

      expect(
        controller.richText,
        RichText('bolder', const [Entity(0, 6, EntityKind.bold)]),
      );

      controller.commitComposition('bolder');

      expect(
        controller.richText,
        RichText('bolder', const [Entity(0, 6, EntityKind.bold)]),
      );
    });
  });
}
