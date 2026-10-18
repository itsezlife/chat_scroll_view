/// The composer's selection menu: the reference client's floating toolbar,
/// mounted by the field on every platform.
///
/// **Seam:** a `ComposerView` over a `ComposerController`, its toolbar shown
/// with `showToolbar` as the platform does, read through the laid-out sizes,
/// the semantics tree, the key events and a fake clock.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/selection_menu_harness.dart';

final _strings = ChromeStringsPresets.english.formatting;

void main() {
  const long = RichText.plain('one two three four five six seven');
  const select = TextSelection(baseOffset: 4, extentOffset: 7);

  Future<void> pump(WidgetTester tester, int milliseconds) =>
      tester.pump(Duration(milliseconds: milliseconds));

  group('geometry', () {
    testWidgets('the row is 48 dp tall and its items sit flush', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);

      expect(rig.cardSize.height, 48);
      final copy = tester.getRect(MenuRig.item(SelectionMenuItemKind.copy));
      final cut = tester.getRect(MenuRig.item(SelectionMenuItemKind.cut));
      expect(copy.height, 48);
      expect(cut.height, 48);
      expect(cut.right, copy.left);
    });

    testWidgets('an item is its label and 16 dp each side, 24 at the end', (
      tester,
    ) async {
      await MenuRig.show(tester);

      // Ahem draws a 14 dp square per character; Cut is the first item.
      final cut = tester.getSize(MenuRig.item(SelectionMenuItemKind.cut));
      final copy = tester.getSize(MenuRig.item(SelectionMenuItemKind.copy));
      expect(cut.width, 24 + 3 * 14 + 16);
      expect(copy.width, 16 + 4 * 14 + 16);
    });

    testWidgets('the label is 14 dp, weight 500', (tester) async {
      await MenuRig.show(tester);

      final text = tester.widget<Text>(find.text('Copy'));
      expect(text.style!.fontSize, 14);
      expect(text.style!.fontWeight, FontWeight.w500);
    });

    testWidgets('the More button is 56 by 48 and flush with the card end', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);

      expect(tester.getSize(MenuRig.more), const Size(56, 48));
      expect(
        tester.getRect(MenuRig.more).right,
        tester.getRect(MenuRig.card).right,
      );
      expect(rig.cardSize.width, greaterThan(56));
    });

    testWidgets('the card has a 12 dp radius, elevation 1 and the token fill', (
      tester,
    ) async {
      await MenuRig.show(tester);

      final material = tester.widget<Material>(
        find
            .descendant(of: MenuRig.card, matching: find.byType(Material))
            .first,
      );
      expect(material.elevation, 1);
      expect(material.color, const Color(0xFFFFFFFF));
      expect(
        material.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );
      expect(material.clipBehavior, Clip.antiAlias);
    });

    testWidgets('the dark theme takes its fill and text from the tokens', (
      tester,
    ) async {
      await MenuRig.show(tester, brightness: Brightness.dark);

      final tokens = SelectionMenuTokens.fromPalette(
        ChromePalette.forBrightness(Brightness.dark),
      );
      final material = tester.widget<Material>(
        find
            .descendant(of: MenuRig.card, matching: find.byType(Material))
            .first,
      );
      expect(material.color, tokens.background);
      expect(tester.widget<Text>(find.text('Copy')).style!.color, tokens.text);
    });

    testWidgets('the page is sized to its items up to 264 dp with a peek', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      await rig.openMore();

      // Five or more overflow items: four rows, the back row, half a row.
      expect(rig.cardSize.height, 264);
      expect(rig.cardSize.width, greaterThanOrEqualTo(56));
    });

    testWidgets('a short page is as tall as its rows and the back row', (
      tester,
    ) async {
      final rig = await MenuRig.show(
        tester,
        spec: ComposerSpec(
          formatting: const {
            ComposerFormattingOption.bold,
            ComposerFormattingOption.italic,
          },
        ),
      );
      // Cut, Copy and Select all fill the row; Bold and Italic are the page.
      expect(MenuRig.more, findsOneWidget);
      await rig.openMore();

      expect(rig.cardSize.height, 2 * 48 + 48);
      expect(
        find.descendant(of: MenuRig.card, matching: find.byType(ShaderMask)),
        findsNothing,
      );
    });

    testWidgets('overflow rows are 42 dp tall with 18 dp of padding', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      await rig.openMore();

      final bold = tester.getRect(MenuRig.item(SelectionMenuItemKind.bold));
      expect(bold.height, 42);
      final label = tester.getRect(find.text('Bold'));
      expect(label.left - bold.left, 18);
    });

    testWidgets(
      'the back row is 48 tall, its label 16 dp at 56 from the start',
      (tester) async {
        final rig = await MenuRig.show(tester);
        await rig.openMore();

        final row = tester.getRect(MenuRig.more);
        expect(row.height, 48);
        expect(row.left, tester.getRect(MenuRig.card).left);
        final label = tester.getRect(find.text(_strings.backAction));
        expect(label.left - row.left, 56);
        final style = tester
            .widget<Text>(find.text(_strings.backAction))
            .style!;
        expect(style.fontSize, 16);
        expect(style.fontWeight, FontWeight.w400);
      },
    );

    testWidgets('the hairline above the back row is one physical pixel', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      final rig = await MenuRig.show(tester);
      await rig.openMore();

      final hairline = find.descendant(
        of: find.byKey(const ValueKey<String>('back')),
        matching: find.byType(ColoredBox),
      );
      expect(tester.getSize(hairline).height, 0.5);
    });

    testWidgets('the page fades its rows at the edges when it scrolls', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      expect(
        find.descendant(of: MenuRig.card, matching: find.byType(ShaderMask)),
        findsNothing,
      );

      await rig.openMore();

      expect(
        find.descendant(of: MenuRig.card, matching: find.byType(ShaderMask)),
        findsOneWidget,
      );
    });

    testWidgets('the card keeps 16 dp from the screen and fits a narrow one', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, size: const Size(300, 600));

      final rect = tester.getRect(MenuRig.card);
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(300 - 16));
      expect(rig.cardSize.width, lessThanOrEqualTo(300 - 32));
    });

    testWidgets('on a wide screen the card is no wider than 400 dp', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, size: const Size(1400, 600));

      expect(rig.cardSize.width, lessThanOrEqualTo(400));
    });

    testWidgets('the card sits above the selection with 8 dp between', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);

      final render = rig.editable.renderEditable;
      final selection = render.getBoxesForSelection(select);
      final top = render.localToGlobal(selection.first.toRect().topLeft).dy;
      expect(tester.getRect(MenuRig.card).bottom, closeTo(top - 8, 1));
    });

    testWidgets('the label follows the text scale up to 1.3', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await MenuRig.show(tester);

      final cut = tester.getSize(find.text('Cut'));
      expect(cut.width, closeTo(3 * 14 * 1.15, 0.5));

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pump();
      await tester.pump();
      // A larger scale is clamped: the rows are fixed-height.
      expect(
        tester.getSize(find.text('Cut')).width,
        closeTo(3 * 14 * 1.3, 0.5),
      );
    });
  });

  group('items', () {
    Future<MenuRig> showWith(
      WidgetTester tester, {
      RichText text = long,
      TextSelection selection = select,
      ComposerSpec? spec,
    }) => MenuRig.show(
      tester,
      text: text,
      selection: selection,
      spec: spec,
      size: const Size(800, 900),
    );

    testWidgets('every formatting item calls its command', (tester) async {
      for (final (kind, entity) in [
        (SelectionMenuItemKind.bold, EntityKind.bold),
        (SelectionMenuItemKind.italic, EntityKind.italic),
        (SelectionMenuItemKind.underline, EntityKind.underline),
        (SelectionMenuItemKind.strikethrough, EntityKind.strike),
        (SelectionMenuItemKind.spoiler, EntityKind.spoiler),
        (SelectionMenuItemKind.mono, EntityKind.code),
      ]) {
        final rig = await showWith(tester);

        await rig.tapItem(kind);

        expect(rig.composer.richText.entities, [
          Entity(4, 3, entity),
        ], reason: '$kind');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('Quote and Code block act on the line', (tester) async {
      var rig = await showWith(tester);
      await rig.tapItem(SelectionMenuItemKind.quote);
      expect(rig.composer.richText.entities, [
        const Entity(0, 33, EntityKind.quote),
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      rig = await showWith(tester);
      await rig.tapItem(SelectionMenuItemKind.codeBlock);
      expect(rig.composer.richText.entities, [
        const Entity(0, 33, EntityKind.codeBlock()),
      ]);
    });

    testWidgets('Regular clears the formatting', (tester) async {
      final rig = await showWith(
        tester,
        text: RichText('bold word', const [Entity(0, 4, EntityKind.bold)]),
        selection: const TextSelection(baseOffset: 0, extentOffset: 4),
      );

      await rig.tapItem(SelectionMenuItemKind.clearFormatting);

      expect(rig.composer.richText, const RichText.plain('bold word'));
    });

    testWidgets('an item closes the menu and leaves a caret at the end', (
      tester,
    ) async {
      final rig = await showWith(tester);

      await rig.tapItem(SelectionMenuItemKind.bold);

      expect(MenuRig.card, findsNothing);
      expect(rig.composer.selection, const TextSelection.collapsed(offset: 7));
    });

    testWidgets('a bold selection is spoken as selected on Bold', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await showWith(
        tester,
        text: RichText('bold word', const [Entity(0, 4, EntityKind.bold)]),
        selection: const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      await rig.openMore();

      expect(
        tester.getSemantics(find.bySemanticsLabel(_strings.boldAction)),
        isSemantics(
          label: _strings.boldAction,
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a quoted selection has no Quote item', (tester) async {
      final rig = await showWith(
        tester,
        text: RichText('quoted text', const [Entity(0, 11, EntityKind.quote)]),
        selection: const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      await rig.openMore();

      expect(MenuRig.item(SelectionMenuItemKind.quote), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.bold), findsOneWidget);
    });

    testWidgets('a selection in code has no item code cannot take', (
      tester,
    ) async {
      final rig = await showWith(
        tester,
        text: RichText('some code', const [Entity(5, 4, EntityKind.code)]),
        selection: const TextSelection(baseOffset: 6, extentOffset: 8),
      );
      await rig.openMore();

      expect(MenuRig.item(SelectionMenuItemKind.bold), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.italic), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.mono), findsOneWidget);
    });

    testWidgets('a collapsed caret gets no formatting', (tester) async {
      final rig = await showWith(
        tester,
        selection: const TextSelection.collapsed(offset: 4),
      );

      expect(MenuRig.item(SelectionMenuItemKind.bold), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.selectAll), findsOneWidget);
      expect(rig.cardSize.height, 48);
    });

    testWidgets('the spec\'s options choose the items', (tester) async {
      final rig = await showWith(
        tester,
        spec: ComposerSpec(formatting: const {ComposerFormattingOption.bold}),
      );
      if (MenuRig.more.evaluate().isNotEmpty) await rig.openMore();

      expect(MenuRig.item(SelectionMenuItemKind.bold), findsOneWidget);
      expect(MenuRig.item(SelectionMenuItemKind.italic), findsNothing);
    });

    testWidgets('select all keeps the menu up over the whole text', (
      tester,
    ) async {
      final rig = await showWith(tester);

      await rig.tapItem(SelectionMenuItemKind.selectAll);

      expect(MenuRig.card, findsOneWidget);
      expect(
        rig.composer.selection,
        const TextSelection(baseOffset: 0, extentOffset: 33),
      );
    });
  });

  group('links', () {
    Future<MenuRig> showLink(
      WidgetTester tester,
      List<String?> asked, {
      String? answer = 'https://x.y',
      RichText text = long,
      TextSelection selection = select,
    }) => MenuRig.show(
      tester,
      text: text,
      selection: selection,
      size: const Size(800, 900),
      spec: ComposerSpec(
        linkPrompt: (context, current) async {
          asked.add(current);
          return answer;
        },
      ),
    );

    testWidgets('Create asks the prompt and links the selection', (
      tester,
    ) async {
      final asked = <String?>[];
      final rig = await showLink(tester, asked);

      await rig.tapItem(SelectionMenuItemKind.createLink);

      expect(asked, [null]);
      expect(rig.composer.richText.entities, [
        const Entity(4, 3, EntityKind.link('https://x.y')),
      ]);
    });

    testWidgets('Edit hands the prompt the current URL and replaces it', (
      tester,
    ) async {
      final asked = <String?>[];
      final rig = await showLink(
        tester,
        asked,
        text: RichText('see link', const [
          Entity(4, 4, EntityKind.link('https://old.example')),
        ]),
        selection: const TextSelection(baseOffset: 4, extentOffset: 8),
      );

      await rig.tapItem(SelectionMenuItemKind.editLink);

      expect(asked, ['https://old.example']);
      expect(rig.composer.richText.entities, [
        const Entity(4, 4, EntityKind.link('https://x.y')),
      ]);
    });

    testWidgets('a prompt that is cancelled changes nothing', (tester) async {
      final asked = <String?>[];
      final rig = await showLink(tester, asked, answer: null);

      await rig.tapItem(SelectionMenuItemKind.createLink);

      expect(asked, hasLength(1));
      expect(rig.composer.richText, long);
    });

    testWidgets('Remove takes the link off and keeps the text', (tester) async {
      final asked = <String?>[];
      final rig = await showLink(
        tester,
        asked,
        text: RichText('see link', const [
          Entity(4, 4, EntityKind.link('https://old.example')),
        ]),
        selection: const TextSelection(baseOffset: 4, extentOffset: 8),
      );

      await rig.tapItem(SelectionMenuItemKind.removeLink);

      expect(asked, isEmpty);
      expect(rig.composer.richText, const RichText.plain('see link'));
    });

    testWidgets('without a prompt there is no link item', (tester) async {
      final rig = await MenuRig.show(
        tester,
        spec: ComposerSpec(),
        size: const Size(800, 900),
      );
      await rig.openMore();

      expect(MenuRig.item(SelectionMenuItemKind.createLink), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.bold), findsOneWidget);
    });
  });

  group('motion', () {
    // A ticker's first frame is its start: an animation begun in a callback
    // reads zero at the next frame, and progresses from there. `start` is that
    // frame.
    Future<void> start(WidgetTester tester) => tester.pump();

    testWidgets('the card comes in over 150 ms', (tester) async {
      final rig = await MenuRig.show(tester, enter: false);

      expect(rig.opacity, 0);
      await start(tester);
      await pump(tester, 75);
      // The curve is symmetric: half way through, half way up.
      expect(rig.opacity, closeTo(0.5, 0.01));
      await pump(tester, 74);
      expect(rig.opacity, lessThan(1));
      await pump(tester, 2);
      expect(rig.opacity, 1);
    });

    testWidgets('an item holds the card 150 ms, then fades it over 100', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);

      await tester.tap(MenuRig.item(SelectionMenuItemKind.copy));
      await tester.pump();
      await pump(tester, 140);
      expect(rig.opacity, 1);
      // The delay ends at 150 ms; the fade begins on the frame after.
      await pump(tester, 15);
      await pump(tester, 50);
      expect(rig.opacity, closeTo(0.5, 0.01));
      expect(MenuRig.card, findsOneWidget);
      await pump(tester, 60);
      await tester.pump();
      expect(MenuRig.card, findsNothing);
    });

    testWidgets('the page unfolds over 250 ms: the height leads the width', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      final closed = rig.cardSize;
      await tester.tap(MenuRig.more);
      await start(tester);

      await pump(tester, 80);
      final early = rig.cardSize;
      // The height eases out of the start; the width starts slowly.
      final heightDone = (early.height - closed.height) / (264 - closed.height);
      final widthDone = (closed.width - early.width) / (closed.width - 218);
      expect(heightDone, greaterThan(0.2));
      expect(widthDone, lessThan(0.1));
      expect(rig.cardState.isAnimating, isTrue);

      await pump(tester, 160);
      expect(rig.cardState.isAnimating, isTrue);
      await pump(tester, 20);
      expect(rig.cardState.isAnimating, isFalse);
      expect(rig.cardSize, const Size(218, 264));
    });

    testWidgets('closing runs it back: the width leads the height', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      await rig.openMore();
      final open = rig.cardSize;
      await tester.tap(MenuRig.more);
      await start(tester);

      await pump(tester, 80);
      final early = rig.cardSize;
      final widthDone = (early.width - open.width) / (398 - open.width);
      final heightDone = (open.height - early.height) / (open.height - 48);
      expect(widthDone, greaterThan(0.2));
      expect(heightDone, lessThan(0.1));

      await pump(tester, 300);
      expect(rig.cardSize, const Size(398, 48));
    });

    testWidgets('the row fades out over 250 ms as the page opens', (
      tester,
    ) async {
      await MenuRig.show(tester);
      await tester.tap(MenuRig.more);
      await start(tester);

      FadeTransition fadeOf(String key) => tester.widget<FadeTransition>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(FadeTransition),
        ),
      );
      await pump(tester, 100);
      expect(fadeOf('main').opacity.value, inExclusiveRange(0, 1));
      expect(fadeOf('overflow').opacity.value, 1);
      await pump(tester, 160);
      expect(find.byKey(const ValueKey<String>('main')), findsNothing);
    });

    testWidgets('pointers are absorbed while the page unfolds', (tester) async {
      final rig = await MenuRig.show(tester);
      await tester.tap(MenuRig.more);
      await start(tester);
      await pump(tester, 60);

      expect(rig.cardState.isAnimating, isTrue);
      await tester.tap(MenuRig.more, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The second tap would have closed the page again.
      expect(rig.cardState.isOpen, isTrue);
    });

    testWidgets('a scroll hides the card over 100 ms and it comes back', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      final overlay = rig.editable.selectionOverlay!;

      overlay.suppressToolbarForScroll(true);
      await start(tester);
      await pump(tester, 50);
      expect(rig.opacity, closeTo(0.5, 0.01));
      await pump(tester, 60);
      expect(rig.opacity, 0);

      overlay.suppressToolbarForScroll(false);
      await start(tester);
      await pump(tester, 151);
      expect(rig.opacity, 1);
    });

    testWidgets('the page stays open through a hide and a show', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      await rig.openMore();
      final overlay = rig.editable.selectionOverlay!;

      overlay.suppressToolbarForScroll(true);
      await tester.pumpAndSettle();
      expect(rig.opacity, 0);
      overlay.suppressToolbarForScroll(false);
      await tester.pumpAndSettle();

      expect(rig.opacity, 1);
      expect(rig.cardState.isOpen, isTrue);
      expect(rig.cardSize.height, 264);
    });

    testWidgets('a moving selection does not hide a card shown under 500 ms', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, enter: false);
      await start(tester);
      await pump(tester, 200);

      rig.composer.select(const TextSelection(baseOffset: 8, extentOffset: 11));
      await tester.pump();
      await pump(tester, 1);
      await pump(tester, 60);

      expect(rig.opacity, 1);
    });

    testWidgets(
      'after 500 ms a moving selection hides it, and it returns 50 ms after the move stops',
      (tester) async {
        final rig = await MenuRig.show(tester);
        await pump(tester, 600);

        rig.composer.select(
          const TextSelection(baseOffset: 8, extentOffset: 11),
        );
        await tester.pump();
        await start(tester);
        await pump(tester, 110);
        expect(rig.opacity, 0);

        // Still moving: it stays away while the selection keeps changing.
        rig.composer.select(
          const TextSelection(baseOffset: 0, extentOffset: 3),
        );
        await tester.pump();
        await pump(tester, 30);
        expect(rig.opacity, 0);

        // 50 ms after the last move it comes back, over 150 ms.
        await pump(tester, 40);
        await start(tester);
        await pump(tester, 75);
        expect(rig.opacity, closeTo(0.5, 0.05));
        await pump(tester, 80);
        expect(rig.opacity, 1);
      },
    );
  });

  group('semantics', () {
    testWidgets('every item has its label from the strings', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      for (final label in ['Cut', 'Copy', _strings.moreAction]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await rig.openMore();
      for (final label in [
        _strings.quoteAction,
        _strings.spoilerAction,
        _strings.boldAction,
        _strings.italicAction,
        _strings.monoAction,
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      expect(find.bySemanticsLabel(_strings.backAction), findsWidgets);
      handle.dispose();
    });

    testWidgets('a row out of sight is not spoken', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      expect(find.bySemanticsLabel(_strings.boldAction), findsNothing);
      await rig.openMore();
      expect(find.bySemanticsLabel('Cut'), findsNothing);
      handle.dispose();
    });
  });

  group('keyboard', () {
    Rect focused() => FocusManager.instance.primaryFocus!.rect;

    testWidgets('Tab moves focus into the menu and Enter chooses an item', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // The first item, Cut, and the field is still the focused field: the
      // editable would close its toolbar if it lost focus.
      expect(
        focused(),
        tester.getRect(MenuRig.item(SelectionMenuItemKind.cut)),
      );
      expect(rig.composer.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await rig.settle();
      expect(rig.composer.richText.plain.length, lessThan(33));
      expect(MenuRig.card, findsNothing);
      expect(rig.composer.focusNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('Tab and Shift+Tab move between the items, and wrap', (
      tester,
    ) async {
      await MenuRig.show(tester);
      Rect rectOf(SelectionMenuItemKind kind) =>
          tester.getRect(MenuRig.item(kind));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(), rectOf(SelectionMenuItemKind.copy));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      // Back past Cut to the More button.
      expect(focused(), tester.getRect(MenuRig.more));
    });

    testWidgets('the arrow keys move between the items', (tester) async {
      await MenuRig.show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(
        focused(),
        tester.getRect(MenuRig.item(SelectionMenuItemKind.copy)),
      );
    });

    testWidgets('Enter on the More button opens the page', (tester) async {
      final rig = await MenuRig.show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(rig.cardState.isOpen, isTrue);
    });

    testWidgets('Escape closes the menu and leaves a caret', (tester) async {
      final rig = await MenuRig.show(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await rig.settle();

      expect(MenuRig.card, findsNothing);
      expect(rig.composer.selection.isCollapsed, isTrue);
    });
  });

  group('back', () {
    testWidgets('the system back closes the menu and keeps the route', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);

      final handled = await tester.binding.handlePopRoute();
      await rig.settle();

      expect(handled, isTrue);
      expect(MenuRig.card, findsNothing);
      expect(rig.composer.hasFocus, isTrue);
    });

    testWidgets('with the overflow page open Back closes the page first, then '
        'the menu', (tester) async {
      final rig = await MenuRig.show(tester);
      await rig.openMore();
      expect(rig.cardState.isOpen, isTrue);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await rig.settle();

      expect(MenuRig.card, findsOneWidget);
      expect(rig.cardState.isOpen, isFalse);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await rig.settle();

      expect(MenuRig.card, findsNothing);
    });

    testWidgets('the host\'s hook takes Back while the menu is up', (
      tester,
    ) async {
      final calls = <String>[];
      ValueGetter<Future<bool>>? onBack;
      final rig = await MenuRig.show(
        tester,
        spec: ComposerSpec(
          backPriority: (callback) {
            calls.add('acquire');
            onBack = callback;
            return () => calls.add('release');
          },
        ),
        enter: false,
      );
      await pump(tester, 300);

      expect(calls, ['acquire']);
      expect(await onBack!(), isTrue);
      await rig.settle();

      expect(calls, ['acquire', 'release']);
      expect(rig.composer.hasFocus, isTrue);
    });
  });

  group('right to left', () {
    testWidgets('the card keeps its start edge and the More button is first', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, textDirection: TextDirection.rtl);

      final card = tester.getRect(MenuRig.card);
      expect(tester.getRect(MenuRig.more).left, card.left);
      expect(
        tester.getRect(MenuRig.item(SelectionMenuItemKind.cut)).right,
        card.right,
      );

      await rig.openMore();
      final back = tester.getRect(MenuRig.more);
      expect(back.left, tester.getRect(MenuRig.card).left);
      // The label starts at the right edge of the row.
      final label = tester.getRect(find.text(_strings.backAction));
      expect(back.right - label.right, 56);
    });

    testWidgets('the page opens from the same edge it closes to', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, textDirection: TextDirection.rtl);
      final left = tester.getRect(MenuRig.card).left;

      await rig.openMore();

      expect(tester.getRect(MenuRig.card).left, left);
    });
  });

  testWidgets(
    'is the composer\'s own menu on every platform',
    (tester) async {
      await MenuRig.show(tester);

      expect(MenuRig.card, findsOneWidget);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    },
    variant: TargetPlatformVariant.all(),
  );
}
