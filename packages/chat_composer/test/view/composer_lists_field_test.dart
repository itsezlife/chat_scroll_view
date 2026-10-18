/// List editing on the field: the keys, the platform's typing and the gutter's
/// room.
///
/// **Seam:** [ComposerView] over a [ComposerController] whose text edits
/// lists, driven by key events and the platform text input, observed through
/// the rich text.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

const _bullet = EntityKind.list(listKind: EntityListKind.bullet);
const _bullet1 = EntityKind.list(listKind: EntityListKind.bullet, depth: 1);
const _ordered = EntityKind.list(listKind: EntityListKind.ordered);

void main() {
  late ComposerController controller;

  var sends = 0;

  Future<void> show(WidgetTester tester, {bool lists = true}) async {
    sends = 0;
    controller = ComposerController(text: ComposerTextController(lists: lists));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      composerHarness(
        ComposerView(
          controller: controller,
          spec: ComposerSpec(
            actions: [
              ActionDescriptor(
                id: 'send',
                icon: ChromeIconId.send,
                semanticLabel: 'Send',
                primary: true,
                onTap: () => sends++,
              ),
            ],
          ),
          shortcuts: const ComposerShortcutPolicy.desktop().shortcuts,
        ),
      ),
    );
    controller.requestFocus();
    await tester.pump();
  }

  void load(RichText text, int caret) {
    controller.text.restore(
      text,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool control = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  // What the platform reports for one keystroke: the whole value, with the
  // caret after what was typed.
  Future<void> typeKey(WidgetTester tester, String typed) async {
    final value = controller.text.value;
    final selection = value.selection;
    final text = value.text.replaceRange(selection.start, selection.end, typed);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: selection.start + typed.length,
        ),
      ),
    );
    await tester.pump();
  }

  double gutterInset(WidgetTester tester) => tester
      .widget<ExtendedTextField>(find.byType(ExtendedTextField))
      .gutterInset;

  group('with lists on', () {
    testWidgets('typing "- " then text makes a bullet item', (tester) async {
      await show(tester);

      await typeKey(tester, '-');
      await typeKey(tester, ' ');
      await typeKey(tester, 'a');

      expect(controller.richText, RichText('a', const [Entity(0, 1, _bullet)]));
    });

    testWidgets('Enter, Enter leaves the list and the next line is plain', (
      tester,
    ) async {
      await show(tester);
      load(RichText('a', const [Entity(0, 1, _bullet)]), 1);

      await typeKey(tester, '\n');
      await typeKey(tester, 'b');
      await typeKey(tester, '\n');
      await typeKey(tester, '\n');
      await typeKey(tester, 'c');

      expect(
        controller.richText,
        RichText('a\nb\nc', const [
          Entity(0, 1, _bullet),
          Entity(2, 1, _bullet),
        ]),
      );
    });

    testWidgets('Tab indents to at most depth 3 and Shift+Tab outdents', (
      tester,
    ) async {
      await show(tester);
      load(RichText('a', const [Entity(0, 1, _bullet)]), 1);

      for (var i = 0; i < 5; i++) {
        await key(tester, LogicalKeyboardKey.tab);
      }
      expect(
        controller.richText.entities.single.kind,
        const EntityKind.list(listKind: EntityListKind.bullet, depth: 3),
      );

      await key(tester, LogicalKeyboardKey.tab, shift: true);
      expect(
        controller.richText.entities.single.kind,
        const EntityKind.list(listKind: EntityListKind.bullet, depth: 2),
      );
    });

    testWidgets('Shift+Enter inserts a soft break written as two spaces', (
      tester,
    ) async {
      await show(tester);
      load(RichText('a', const [Entity(0, 1, _bullet)]), 1);

      await key(tester, LogicalKeyboardKey.enter, shift: true);
      await typeKey(tester, 'b');

      expect(controller.richText.plain, 'a\nb');
      expect(RichTextMarkdown.encode(controller.richText), '- a  \nb');
    });

    testWidgets('Backspace at the start of the first item leaves the list', (
      tester,
    ) async {
      await show(tester);
      load(RichText('a', const [Entity(0, 1, _bullet1)]), 0);

      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.richText.entities.single.kind, _bullet);

      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.richText, const RichText.plain('a'));
    });

    testWidgets('Backspace inside an item deletes', (tester) async {
      await show(tester);
      load(RichText('ab', const [Entity(0, 2, _bullet)]), 2);

      await key(tester, LogicalKeyboardKey.backspace);

      expect(controller.richText.plain, 'a');
    });

    testWidgets('Ctrl+Shift+8 and Ctrl+Shift+7 toggle the kind', (
      tester,
    ) async {
      await show(tester);
      load(const RichText.plain('one\ntwo'), 7);
      controller.select(const TextSelection(baseOffset: 0, extentOffset: 7));

      await key(tester, LogicalKeyboardKey.digit8, shift: true, control: true);
      expect(
        controller.richText,
        RichText('one\ntwo', const [
          Entity(0, 3, _bullet),
          Entity(4, 3, _bullet),
        ]),
      );

      await key(tester, LogicalKeyboardKey.digit7, shift: true, control: true);
      expect(
        controller.richText,
        RichText('one\ntwo', const [
          Entity(0, 3, _ordered),
          Entity(4, 3, _ordered),
        ]),
      );

      await key(tester, LogicalKeyboardKey.digit7, shift: true, control: true);
      expect(controller.richText, const RichText.plain('one\ntwo'));
    });

    testWidgets('the field makes room for the gutter only while it has one', (
      tester,
    ) async {
      await show(tester);
      expect(gutterInset(tester), 0);

      load(RichText('a', const [Entity(0, 1, _bullet)]), 1);
      await tester.pump();
      expect(gutterInset(tester), greaterThan(0));

      load(const RichText.plain('a'), 1);
      await tester.pump();
      expect(gutterInset(tester), 0);
    });

    testWidgets('a wider number makes the gutter wider', (tester) async {
      await show(tester);
      load(RichText('a', const [Entity(0, 1, _ordered)]), 1);
      await tester.pump();
      final one = gutterInset(tester);

      load(
        RichText(List.filled(10, 'a').join('\n'), [
          for (var i = 0; i < 10; i++) Entity(i * 2, 1, _ordered),
        ]),
        1,
      );
      await tester.pump();

      expect(gutterInset(tester), greaterThan(one));
    });

    testWidgets('an empty item shows its marker', (tester) async {
      await show(tester);
      await typeKey(tester, '-');
      await typeKey(tester, ' ');

      expect(controller.text.listMarkers, hasLength(1));
      expect(gutterInset(tester), greaterThan(0));
    });
  });

  group('Enter to send', () {
    testWidgets('is the list\'s in an item and the send key elsewhere', (
      tester,
    ) async {
      await show(tester);
      load(RichText('a\nb', const [Entity(0, 1, _bullet)]), 1);

      await key(tester, LogicalKeyboardKey.enter);
      expect(sends, 0);

      controller.select(const TextSelection.collapsed(offset: 3));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      expect(sends, 1);
    });

    testWidgets('is the send key in an item with lists off', (tester) async {
      await show(tester, lists: false);
      load(RichText('a', const [Entity(0, 1, _bullet)]), 1);

      await key(tester, LogicalKeyboardKey.enter);

      expect(sends, 1);
    });
  });

  group('with lists off', () {
    testWidgets('the list keys leave the field to its own handling', (
      tester,
    ) async {
      await show(tester, lists: false);
      load(RichText('a', const [Entity(0, 1, _bullet)]), 1);

      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.tab, shift: true);
      await key(tester, LogicalKeyboardKey.enter, shift: true);
      await key(tester, LogicalKeyboardKey.digit8, shift: true, control: true);

      expect(controller.richText, RichText('a', const [Entity(0, 1, _bullet)]));
    });

    testWidgets('typed markers are text and the field has no gutter', (
      tester,
    ) async {
      await show(tester, lists: false);

      await typeKey(tester, '-');
      await typeKey(tester, ' ');
      await typeKey(tester, 'a');

      expect(controller.richText, const RichText.plain('- a'));
      expect(gutterInset(tester), 0);
    });
  });
}
