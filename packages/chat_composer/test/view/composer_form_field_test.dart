/// The composer's field in a form: the editable, its selection menu and lists
/// under the host's decoration, validation and focus.
///
/// **Seam:** a [ComposerFormField] inside a [Form] over a
/// [ComposerController], observed through the controller's rich text, the
/// decoration it draws (label, counter, error) and the selection menu's items.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

void main() {
  late ComposerController controller;
  late GlobalKey<FormState> form;

  Future<void> show(
    WidgetTester tester, {
    ComposerTextController? text,
    InputDecoration decoration = const InputDecoration(labelText: 'About'),
    FormFieldValidator<RichText>? validator,
    Set<ComposerFormattingOption> formatting =
        ComposerFormattingOption.standard,
    ComposerLinkPrompt? linkPrompt,
    int? maxLength,
    FocusNode? focusNode,
    Widget? after,
  }) async {
    controller = ComposerController(text: text, focusNode: focusNode);
    addTearDown(controller.dispose);
    form = GlobalKey<FormState>();
    await tester.pumpWidget(
      composerHarness(
        Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ComposerFormField(
                controller: controller,
                decoration: decoration,
                validator: validator,
                formatting: formatting,
                linkPrompt: linkPrompt,
                maxLength: maxLength,
              ),
              ?after,
            ],
          ),
        ),
        anchoredTop: true,
      ),
    );
  }

  ExtendedEditableTextState editable(WidgetTester tester) =>
      tester.state(find.byType(ExtendedEditableText));

  Finder item(SelectionMenuItemKind kind) =>
      find.byKey(ValueKey<SelectionMenuItemKind>(kind));

  // Selects [selection] of [text] and opens the menu's More page, where the
  // formatting items are.
  Future<void> openMenu(
    WidgetTester tester,
    RichText text, {
    TextSelection selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    ),
  }) async {
    // Focus first, as a tap gives it: the editable makes its selection
    // overlay when it gains focus.
    controller.requestFocus();
    await tester.pump();
    controller.restore(text, selection: selection);
    await tester.pump();
    expect(editable(tester).showToolbar(), isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SelectionMenuRootPage.moreKey));
    await tester.pumpAndSettle();
  }

  Future<void> tapItem(WidgetTester tester, SelectionMenuItemKind kind) async {
    final finder = item(kind);
    await tester.scrollUntilVisible(
      finder,
      42,
      scrollable: find
          .descendant(
            of: find.byType(SelectionMenuCard),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  group('validation', () {
    testWidgets('the validator reads the rich text and its error shows', (
      tester,
    ) async {
      RichText? seen;
      await show(
        tester,
        validator: (value) {
          seen = value;
          return value == null || value.plain.isEmpty ? 'Required' : null;
        },
      );

      expect(find.text('About'), findsOneWidget);
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);

      await enterFieldText(tester, 'hello');
      expect(form.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Required'), findsNothing);
      expect(seen, const RichText.plain('hello'));
    });
    testWidgets('reset brings back the text the field was built with', (
      tester,
    ) async {
      controller = ComposerController();
      controller.restore(const RichText.plain('seed'));
      addTearDown(controller.dispose);
      form = GlobalKey<FormState>();
      await tester.pumpWidget(
        composerHarness(
          Form(
            key: form,
            child: ComposerFormField(controller: controller),
          ),
          anchoredTop: true,
        ),
      );

      await enterFieldText(tester, 'changed');
      expect(controller.richText.plain, 'changed');

      form.currentState!.reset();
      await tester.pump();

      expect(controller.richText, const RichText.plain('seed'));
    });

    testWidgets('a decoration error shows without a validator', (tester) async {
      await show(
        tester,
        decoration: const InputDecoration(errorText: 'From the host'),
      );

      expect(find.text('From the host'), findsOneWidget);
    });
  });

  group('length', () {
    testWidgets('the counter is in code points of the plain text', (
      tester,
    ) async {
      await show(tester, maxLength: 10);
      expect(find.text('0/10'), findsOneWidget);

      // Two surrogate pairs and bold, which costs nothing.
      controller.restore(
        RichText('ab😀😀', const [Entity(0, 2, EntityKind.bold)]),
      );
      await tester.pump();

      expect(find.text('4/10'), findsOneWidget);
    });

    testWidgets('over the limit nothing is trimmed and the counter turns', (
      tester,
    ) async {
      await show(tester, maxLength: 3);

      await enterFieldText(tester, 'hello');

      expect(controller.richText.plain, 'hello');
      final counter = tester.widget<Text>(find.text('5/3'));
      final theme = Theme.of(tester.element(find.text('5/3')));
      expect(
        counter.style?.color ??
            DefaultTextStyle.of(tester.element(find.text('5/3'))).style.color,
        theme.colorScheme.error,
      );
    });
  });

  group('focus', () {
    testWidgets("the controller's focus node is the field's", (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await show(tester, focusNode: node);

      expect(node.hasFocus, isFalse);
      await tester.tap(find.byType(ComposerFormField));
      await tester.pump();

      expect(node.hasFocus, isTrue);
      expect(editable(tester).widget.focusNode, same(node));
    });

    testWidgets('Tab moves on to the next field outside a list', (
      tester,
    ) async {
      await show(
        tester,
        text: ComposerTextController(lists: true),
        after: const TextField(key: Key('next')),
      );
      controller.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.hasFocus, isFalse);
    });
  });

  group('formatting', () {
    testWidgets('the menu offers only the allowed items', (tester) async {
      await show(
        tester,
        formatting: const {
          ComposerFormattingOption.bold,
          ComposerFormattingOption.clearFormatting,
        },
      );

      // Bold text, so Clear formatting has something to clear.
      await openMenu(
        tester,
        RichText('one two', const [Entity(0, 3, EntityKind.bold)]),
      );

      expect(item(SelectionMenuItemKind.bold), findsOneWidget);
      expect(item(SelectionMenuItemKind.italic), findsNothing);
      expect(item(SelectionMenuItemKind.clearFormatting), findsOneWidget);
    });

    testWidgets('an item formats the selection', (tester) async {
      await show(tester);
      await openMenu(tester, const RichText.plain('one two'));

      await tapItem(tester, SelectionMenuItemKind.bold);

      expect(controller.richText.entities, [
        const Entity(0, 3, EntityKind.bold),
      ]);
    });

    testWidgets('the formatting keys apply', (tester) async {
      await show(tester);
      controller
        ..requestFocus()
        ..restore(
          const RichText.plain('one two'),
          selection: const TextSelection(baseOffset: 0, extentOffset: 3),
        );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(controller.richText.entities, [
        const Entity(0, 3, EntityKind.bold),
      ]);
    });
  });

  group('lists', () {
    const bullet = EntityKind.list(listKind: EntityListKind.bullet);

    testWidgets('with lists on the menu makes a list and Tab indents it', (
      tester,
    ) async {
      await show(
        tester,
        text: ComposerTextController(lists: true),
        formatting: const {ComposerFormattingOption.bulletList},
      );
      await openMenu(
        tester,
        const RichText.plain('one'),
        selection: const TextSelection(baseOffset: 0, extentOffset: 3),
      );

      await tapItem(tester, SelectionMenuItemKind.bulletList);
      expect(controller.richText.entities, [const Entity(0, 3, bullet)]);

      controller.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.richText.entities, [
        const Entity(
          0,
          3,
          EntityKind.list(listKind: EntityListKind.bullet, depth: 1),
        ),
      ]);
    });

    testWidgets('with lists off the list items are not offered', (
      tester,
    ) async {
      await show(
        tester,
        formatting: const {
          ComposerFormattingOption.bold,
          ComposerFormattingOption.bulletList,
        },
      );

      await openMenu(tester, const RichText.plain('one'));

      expect(item(SelectionMenuItemKind.bold), findsOneWidget);
      expect(item(SelectionMenuItemKind.bulletList), findsNothing);
    });
  });

  group('links', () {
    testWidgets('the link item asks the host and links the selection', (
      tester,
    ) async {
      final asked = <String?>[];
      await show(
        tester,
        linkPrompt: (context, current) async {
          asked.add(current);
          return 'https://x.y';
        },
      );
      await openMenu(tester, const RichText.plain('one two'));

      await tapItem(tester, SelectionMenuItemKind.createLink);

      expect(asked, [null]);
      expect(controller.richText.entities, [
        const Entity(0, 3, EntityKind.link('https://x.y')),
      ]);
    });

    testWidgets('without a prompt there is no link item', (tester) async {
      await show(tester);
      await openMenu(tester, const RichText.plain('one two'));

      expect(item(SelectionMenuItemKind.createLink), findsNothing);
    });
  });
}
