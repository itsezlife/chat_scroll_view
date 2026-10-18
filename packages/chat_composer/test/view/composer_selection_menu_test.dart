/// The composer's selection menu: a card over the selection with the clipboard
/// actions on a row and the formatting actions on a More page.
///
/// **Seam:** a `ComposerView` over a `ComposerController`, its toolbar shown
/// with `showToolbar` as the platform does, read through the laid-out sizes,
/// the semantics tree, the key events, real pointer events and a fake clock.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';
import '../support/selection_menu_harness.dart';
import '../support/spoken_labels.dart';

final _strings = ChromeStringsPresets.english.formatting;

void main() {
  const long = RichText.plain('one two three four five six seven');
  const select = TextSelection(baseOffset: 4, extentOffset: 7);

  Future<void> pump(WidgetTester tester, int milliseconds) =>
      tester.pump(Duration(milliseconds: milliseconds));

  // A ticker's first frame is its start: an animation begun in a callback
  // reads zero at the next frame, and progresses from there.
  Future<void> start(WidgetTester tester) => tester.pump();

  group('placement', () {
    testWidgets('the card sits 8 dp over the selection', (tester) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      final box = rig.editable.renderEditable
          .getBoxesForSelection(select)
          .first
          .toRect();
      final top = MatrixUtils.transformRect(
        rig.editable.renderEditable.getTransformTo(null),
        box,
      ).top;
      expect(tester.getRect(MenuRig.card).bottom, closeTo(top - 8, 1));
    });

    testWidgets('the card is centred on the selection', (tester) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      final box = MatrixUtils.transformRect(
        rig.editable.renderEditable.getTransformTo(null),
        rig.editable.renderEditable.getBoxesForSelection(select).first.toRect(),
      );
      final card = tester.getRect(MenuRig.card);
      // The card hugs the trailing edge of a row as wide as the page-opened
      // one, so it is not exactly centred; it is over the selection.
      expect(card.center.dx, closeTo(box.center.dx, card.width));
      expect(card.left, greaterThanOrEqualTo(12));
    });

    testWidgets('the card keeps 12 dp from the screen and fits a narrow one', (
      tester,
    ) async {
      await MenuRig.show(tester, size: const Size(260, 700));

      final card = tester.getRect(MenuRig.card);
      expect(card.left, greaterThanOrEqualTo(12));
      expect(card.right, lessThanOrEqualTo(260 - 12));
    });

    testWidgets('on a wide screen the row is no wider than 400 dp', (
      tester,
    ) async {
      await MenuRig.show(tester, size: const Size(1000, 800));

      expect(tester.getSize(MenuRig.card).width, lessThanOrEqualTo(400));
    });

    testWidgets('a long row moves what does not fit to the page', (
      tester,
    ) async {
      // 160 dp is a row of about two buttons.
      final rig = await MenuRig.show(tester, size: const Size(220, 700));
      expect(MenuRig.item(SelectionMenuItemKind.cut), findsOneWidget);
      expect(
        MenuRig.item(SelectionMenuItemKind.selectAll).hitTestable(),
        findsNothing,
      );

      await rig.openMore();

      // Cut, Copy and Select all are the page's first rows, above Bold.
      final all = tester.getRect(MenuRig.item(SelectionMenuItemKind.selectAll));
      final bold = tester.getRect(MenuRig.item(SelectionMenuItemKind.bold));
      expect(all.top, lessThan(bold.top));
    });

    testWidgets('the card follows the selection when it moves', (tester) async {
      final rig = await MenuRig.show(
        tester,
        text: long,
        size: const Size(800, 900),
      );
      final before = tester.getRect(MenuRig.card);

      rig.composer.select(
        const TextSelection(baseOffset: 18, extentOffset: 22),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.getRect(MenuRig.card).left, isNot(before.left));
      expect(rig.opacity, 1);
    });

    testWidgets('the label follows the text scale up to 1.3', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await MenuRig.show(tester, size: const Size(800, 900));
      final base = tester.getSize(find.text('Copy')).width;

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpWidget(const SizedBox.shrink());
      await MenuRig.show(tester, size: const Size(800, 900));

      expect(tester.getSize(find.text('Copy')).width, closeTo(base * 1.3, 1));
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

    testWidgets('the main row is the clipboard actions and the More button', (
      tester,
    ) async {
      await showWith(tester);

      for (final kind in [
        SelectionMenuItemKind.cut,
        SelectionMenuItemKind.copy,
        SelectionMenuItemKind.selectAll,
      ]) {
        expect(
          MenuRig.item(kind).hitTestable(),
          findsOneWidget,
          reason: '$kind',
        );
      }
      expect(
        MenuRig.item(SelectionMenuItemKind.bold).hitTestable(),
        findsNothing,
      );
      expect(MenuRig.more, findsOneWidget);
    });

    testWidgets('the page lists the formatting in order, Back at the bottom', (
      tester,
    ) async {
      final rig = await showWith(
        tester,
        spec: ComposerSpec(
          formatting: ComposerFormattingOption.standard,
          linkPrompt: (context, _) async => null,
        ),
      );
      await rig.openMore();

      // Nine rows, then Clear formatting, scrolling under 320 dp.
      final order = [
        SelectionMenuItemKind.bold,
        SelectionMenuItemKind.italic,
        SelectionMenuItemKind.underline,
        SelectionMenuItemKind.strikethrough,
        SelectionMenuItemKind.mono,
        SelectionMenuItemKind.spoiler,
        SelectionMenuItemKind.quote,
      ];
      var previous = double.negativeInfinity;
      for (final kind in order) {
        final top = tester.getTopLeft(MenuRig.item(kind)).dy;
        expect(top, greaterThan(previous), reason: '$kind');
        previous = top;
      }
      expect(
        tester.getRect(MenuRig.back).top,
        greaterThan(tester.getRect(MenuRig.item(order.first)).top),
      );
    });

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

    testWidgets('Clear formatting clears the formatting', (tester) async {
      final rig = await showWith(
        tester,
        text: RichText('bold word', const [Entity(0, 4, EntityKind.bold)]),
        selection: const TextSelection(baseOffset: 0, extentOffset: 4),
      );

      await rig.tapItem(SelectionMenuItemKind.clearFormatting);

      expect(rig.composer.richText, const RichText.plain('bold word'));
    });

    testWidgets('an item closes the menu and leaves a caret at the extent', (
      tester,
    ) async {
      final rig = await showWith(tester);

      await rig.tapItem(SelectionMenuItemKind.bold);

      expect(MenuRig.card, findsNothing);
      expect(rig.composer.selection, const TextSelection.collapsed(offset: 7));
    });

    testWidgets('a backwards selection collapses to its extent', (
      tester,
    ) async {
      final rig = await showWith(
        tester,
        selection: const TextSelection(baseOffset: 7, extentOffset: 4),
      );

      await rig.tapItem(SelectionMenuItemKind.bold);

      expect(rig.composer.selection, const TextSelection.collapsed(offset: 4));
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
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
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

    testWidgets('a selection in code greys what code cannot take', (
      tester,
    ) async {
      final rig = await showWith(
        tester,
        text: RichText('some code', const [Entity(5, 4, EntityKind.code)]),
        selection: const TextSelection(baseOffset: 6, extentOffset: 8),
      );
      await rig.openMore();

      final bold = tester.widget<Text>(
        find.descendant(
          of: MenuRig.item(SelectionMenuItemKind.bold),
          matching: find.byType(Text),
        ),
      );
      final mono = tester.widget<Text>(
        find.descendant(
          of: MenuRig.item(SelectionMenuItemKind.mono),
          matching: find.byType(Text),
        ),
      );
      expect(bold.style!.color!.a, closeTo(0.38, 0.01));
      expect(mono.style!.color!.a, 1);

      // Tapping a greyed row does nothing and keeps the menu.
      await tester.tap(MenuRig.item(SelectionMenuItemKind.bold));
      await tester.pumpAndSettle();
      expect(MenuRig.card, findsOneWidget);
      expect(rig.composer.richText.entities, [
        const Entity(5, 4, EntityKind.code),
      ]);
    });

    testWidgets('a collapsed caret gets the page, with only line kinds and '
        'Link on', (tester) async {
      final rig = await showWith(
        tester,
        selection: const TextSelection.collapsed(offset: 4),
      );

      // Select all and More, and nothing to cut or copy.
      expect(MenuRig.item(SelectionMenuItemKind.selectAll), findsOneWidget);
      expect(MenuRig.item(SelectionMenuItemKind.cut), findsNothing);
      expect(MenuRig.more, findsOneWidget);
      await rig.openMore();

      Color? colorOf(SelectionMenuItemKind kind) => tester
          .widget<Text>(
            find.descendant(
              of: MenuRig.item(kind),
              matching: find.byType(Text),
            ),
          )
          .style!
          .color;
      expect(colorOf(SelectionMenuItemKind.bold)!.a, closeTo(0.38, 0.01));
      expect(colorOf(SelectionMenuItemKind.quote)!.a, 1);

      await tester.tap(MenuRig.item(SelectionMenuItemKind.bold));
      await tester.pumpAndSettle();
      expect(rig.composer.richText, long);

      await rig.tapItem(SelectionMenuItemKind.quote);
      expect(rig.composer.richText.entities, [
        const Entity(0, 33, EntityKind.quote),
      ]);
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

    testWidgets('a composer with lists on offers Bullet and Numbered', (
      tester,
    ) async {
      final rig = await MenuRig.show(
        tester,
        size: const Size(800, 900),
        controller: ComposerController(
          text: ComposerTextController(lists: true),
        ),
        spec: ComposerSpec(formatting: ComposerFormattingOption.all),
      );
      addTearDown(rig.composer.dispose);
      if (MenuRig.more.evaluate().isNotEmpty) await rig.openMore();
      // The page builds its rows lazily: scroll to the last of the three.
      await tester.scrollUntilVisible(
        MenuRig.item(SelectionMenuItemKind.numberedList),
        42,
        scrollable: find
            .descendant(of: MenuRig.card, matching: find.byType(Scrollable))
            .first,
      );

      expect(MenuRig.item(SelectionMenuItemKind.bulletList), findsOneWidget);
      expect(MenuRig.item(SelectionMenuItemKind.numberedList), findsOneWidget);
      expect(find.text(_strings.bulletListAction), findsOneWidget);
      expect(find.text(_strings.numberedListAction), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
    });

    testWidgets('a composer with lists off shows no list item', (tester) async {
      final rig = await MenuRig.show(
        tester,
        size: const Size(800, 900),
        spec: ComposerSpec(formatting: ComposerFormattingOption.all),
      );
      if (MenuRig.more.evaluate().isNotEmpty) await rig.openMore();
      await tester.scrollUntilVisible(
        MenuRig.item(SelectionMenuItemKind.clearFormatting),
        42,
        scrollable: find
            .descendant(of: MenuRig.card, matching: find.byType(Scrollable))
            .first,
      );

      expect(
        MenuRig.item(SelectionMenuItemKind.clearFormatting),
        findsOneWidget,
      );
      expect(MenuRig.item(SelectionMenuItemKind.bulletList), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.numberedList), findsNothing);
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

    testWidgets('Paste as plain text follows Paste, on the page when the row '
        'is full', (tester) async {
      // The toolbar offers Paste while the platform says it has text.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => call.method == 'Clipboard.hasStrings'
                ? <String, Object?>{'value': true}
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final rig = await MenuRig.show(
        tester,
        size: const Size(800, 900),
        clipboard: FakeRichClipboard(),
        selection: const TextSelection.collapsed(offset: 4),
      );
      await rig.openMore();

      final paste = tester.getTopLeft(
        MenuRig.item(SelectionMenuItemKind.paste),
      );
      final plain = tester.getTopLeft(
        MenuRig.item(SelectionMenuItemKind.pastePlain),
      );
      final bold = tester.getTopLeft(MenuRig.item(SelectionMenuItemKind.bold));
      expect(plain.dy, lessThan(bold.dy));
      // Paste is on the page too, or on the row before it.
      expect(paste.dy, lessThanOrEqualTo(plain.dy));
    });
  });

  group('clipboard labels', () {
    testWidgets('are Material\'s on every platform', (tester) async {
      await MenuRig.show(tester, size: const Size(800, 900));

      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      // The Cupertino wording is not used where the platform has it.
      expect(find.text('Select All'), findsNothing);
    }, variant: TargetPlatformVariant.all());

    testWidgets(
      'Select all reads as Material\'s over a caret',
      (tester) async {
        await MenuRig.show(
          tester,
          size: const Size(800, 900),
          selection: const TextSelection.collapsed(offset: 4),
        );

        expect(find.text('Select All'), findsNothing);
        // Offered everywhere but on macOS.
        expect(
          find.text('Select all'),
          defaultTargetPlatform == TargetPlatform.macOS
              ? findsNothing
              : findsOneWidget,
        );
      },
      variant: TargetPlatformVariant.all(),
    );
  });

  group('after a clipboard action', () {
    testWidgets(
      'Copy closes the menu and leaves a caret on every platform',
      (tester) async {
        final rig = await MenuRig.show(tester, size: const Size(800, 900));

        await tester.tap(MenuRig.item(SelectionMenuItemKind.copy));
        await rig.settle();

        expect(MenuRig.card, findsNothing);
        expect(
          rig.composer.selection,
          const TextSelection.collapsed(offset: 7),
        );
        expect(
          rig.composer.richText,
          const RichText.plain('one two three four'),
        );
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('Cut removes the selection and closes', (tester) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      await tester.tap(MenuRig.item(SelectionMenuItemKind.cut));
      await rig.settle();

      expect(MenuRig.card, findsNothing);
      expect(rig.composer.richText.plain, 'one  three four');
      expect(rig.composer.selection.isCollapsed, isTrue);
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

    testWidgets('Link asks the prompt and links the selection', (tester) async {
      final asked = <String?>[];
      final rig = await showLink(tester, asked);

      await rig.tapItem(SelectionMenuItemKind.createLink);

      expect(asked, [null]);
      expect(rig.composer.richText.entities, [
        const Entity(4, 3, EntityKind.link('https://x.y')),
      ]);
    });

    testWidgets('over a link it edits: the prompt gets the current URL', (
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

    testWidgets('the selection is kept for the prompt', (tester) async {
      TextSelection? during;
      late ComposerController composer;
      final rig = await MenuRig.show(
        tester,
        size: const Size(800, 900),
        spec: ComposerSpec(
          linkPrompt: (context, current) async {
            during = composer.selection;
            return 'https://x.y';
          },
        ),
      );
      composer = rig.composer;

      await rig.tapItem(SelectionMenuItemKind.createLink);

      expect(during, select);
    });

    testWidgets('a prompt that is cancelled changes nothing', (tester) async {
      final asked = <String?>[];
      final rig = await showLink(tester, asked, answer: null);

      await rig.tapItem(SelectionMenuItemKind.createLink);

      expect(asked, hasLength(1));
      expect(rig.composer.richText, long);
    });

    testWidgets('Remove link takes the link off and keeps the text', (
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

      await rig.tapItem(SelectionMenuItemKind.removeLink);

      expect(asked, isEmpty);
      expect(rig.composer.richText, const RichText.plain('see link'));
    });

    testWidgets('there is no Remove link away from a link', (tester) async {
      final rig = await showLink(tester, []);
      await rig.openMore();
      await tester.scrollUntilVisible(
        MenuRig.item(SelectionMenuItemKind.createLink),
        42,
        scrollable: find
            .descendant(of: MenuRig.card, matching: find.byType(Scrollable))
            .first,
      );

      expect(MenuRig.item(SelectionMenuItemKind.removeLink), findsNothing);
      expect(MenuRig.item(SelectionMenuItemKind.createLink), findsOneWidget);
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
    testWidgets('the card comes in over 150 ms: the wrapper\'s linear fade '
        'times its own ease out', (tester) async {
      final rig = await MenuRig.show(tester, enter: false);

      expect(rig.opacity, 0);
      await start(tester);
      await pump(tester, 75);
      expect(rig.wrapperOpacity, closeTo(0.5, 0.01));
      expect(rig.cardOpacity, closeTo(Curves.easeOut.transform(0.5), 0.01));
      expect(MenuRig.card.evaluate(), isNotEmpty);
      await pump(tester, 76);
      expect(rig.opacity, 1);
    });

    testWidgets('the card enters without moving', (tester) async {
      final rig = await MenuRig.show(tester, enter: false);
      await start(tester);
      await pump(tester, 20);
      final early = tester.getTopLeft(MenuRig.card);

      await tester.pumpAndSettle();

      expect(tester.getTopLeft(MenuRig.card), early);
      expect(rig.opacity, 1);
    });

    testWidgets(
      'an item fades the card out over 220 ms and drifts it up 5 dp',
      (tester) async {
        final rig = await MenuRig.show(tester, size: const Size(800, 900));
        final top = tester.getTopLeft(MenuRig.card).dy;

        await tester.tap(MenuRig.item(SelectionMenuItemKind.copy));
        await start(tester);
        await pump(tester, 110);

        // Half way down the controller, ease-in applied; the wrapper stays up.
        expect(rig.wrapperOpacity, 1);
        expect(rig.cardOpacity, closeTo(Curves.easeIn.transform(0.5), 0.02));
        expect(tester.getTopLeft(MenuRig.card).dy - top, closeTo(-2.5, 0.2));
        expect(MenuRig.card, findsOneWidget);

        await pump(tester, 112);
        await tester.pump();
        expect(MenuRig.card, findsNothing);
      },
    );

    testWidgets('the rows are frozen while the card leaves', (tester) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      await tester.tap(MenuRig.item(SelectionMenuItemKind.copy));
      await start(tester);
      await pump(tester, 100);

      // The selection is a caret by now; Cut and Copy would be gone from a
      // live build.
      expect(rig.composer.selection.isCollapsed, isTrue);
      expect(MenuRig.item(SelectionMenuItemKind.cut), findsOneWidget);
      expect(MenuRig.item(SelectionMenuItemKind.copy), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('the page opens over 300 ms on the CSS ease cubic', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));
      final closed = rig.cardSize;
      await rig.openMore();
      final open = rig.cardSize;
      await tester.tap(MenuRig.back);
      await tester.pumpAndSettle();
      expect(rig.cardSize, closed);

      await tester.tap(MenuRig.more);
      await start(tester);
      await pump(tester, 150);

      final progress = const Cubic(0.25, 0.1, 0.25, 1).transform(0.5);
      final size = rig.cardSize;
      expect(
        size.width,
        closeTo(closed.width + (open.width - closed.width) * progress, 1),
      );
      expect(
        size.height,
        closeTo(closed.height + (open.height - closed.height) * progress, 1),
      );
      await pump(tester, 151);
      expect(rig.cardSize, open);
    });

    testWidgets(
      'the More page is 150 wide and the card is the page\'s height',
      (tester) async {
        final rig = await MenuRig.show(tester, size: const Size(800, 900));
        await rig.openMore();

        expect(rig.cardSize.width, 150);
        // Eight formatting rows under the 320 dp cap: 43 + 8 * 42 = 379 > 313.
        expect(rig.cardSize.height, lessThanOrEqualTo(320));
        expect(rig.cardSize.height, greaterThan(200));
      },
    );

    testWidgets('Back on the page turns it back over 300 ms', (tester) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));
      final closed = rig.cardSize;
      await rig.openMore();

      await tester.tap(MenuRig.back);
      await start(tester);
      await pump(tester, 299);
      expect(rig.cardSize, isNot(closed));
      await pump(tester, 3);

      expect(rig.cardSize, closed);
      expect(rig.isOpen, isFalse);
    });

    testWidgets('a scroll hides the card over 150 ms linear and it comes '
        'back', (tester) async {
      final rig = await MenuRig.show(tester);
      final overlay = rig.editable.selectionOverlay!;

      overlay.suppressToolbarForScroll(true);
      await start(tester);
      await pump(tester, 75);
      expect(rig.opacity, closeTo(0.5, 0.01));
      await pump(tester, 76);
      expect(rig.opacity, 0);

      overlay.suppressToolbarForScroll(false);
      await start(tester);
      await pump(tester, 151);
      expect(rig.opacity, 1);
    });

    testWidgets('a hidden card takes no pointer', (tester) async {
      final rig = await MenuRig.show(tester);
      rig.editable.selectionOverlay!.suppressToolbarForScroll(true);
      await tester.pumpAndSettle();

      expect(
        MenuRig.item(SelectionMenuItemKind.copy).hitTestable(),
        findsNothing,
      );
    });

    testWidgets('the page stays open through a hide and a show', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));
      await rig.openMore();
      final size = rig.cardSize;
      final overlay = rig.editable.selectionOverlay!;

      overlay.suppressToolbarForScroll(true);
      await tester.pumpAndSettle();
      expect(rig.opacity, 0);
      overlay.suppressToolbarForScroll(false);
      await tester.pumpAndSettle();

      expect(rig.opacity, 1);
      expect(rig.isOpen, isTrue);
      expect(rig.cardSize, size);
    });

    testWidgets('a moving selection does not hide the card', (tester) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));
      await pump(tester, 600);

      rig.composer.select(const TextSelection(baseOffset: 8, extentOffset: 11));
      await tester.pump();
      await pump(tester, 60);

      expect(rig.opacity, 1);
    });

    testWidgets('under reduce-motion everything is at once', (tester) async {
      final rig = await MenuRig.show(
        tester,
        size: const Size(800, 900),
        motionSpeed: ChromeMotionSpeed.instant,
      );

      await tester.tap(MenuRig.more);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(rig.isOpen, isTrue);
      expect(rig.cardSize.width, 150);

      await tester.tap(MenuRig.item(SelectionMenuItemKind.bold));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(MenuRig.card, findsNothing);
    });
  });

  group('semantics', () {
    testWidgets('every item has its label', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      for (final label in ['Cut', 'Copy', _strings.moreAction]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await rig.openMore();
      for (final label in [
        _strings.boldAction,
        _strings.italicAction,
        _strings.monoAction,
        _strings.quoteAction,
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      expect(find.bySemanticsLabel(_strings.backAction), findsWidgets);
      handle.dispose();
    });

    testWidgets('a page out of sight is not spoken', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await MenuRig.show(tester, size: const Size(800, 900));

      expect(spokenLabels(tester), isNot(contains(_strings.boldAction)));
      await rig.openMore();
      expect(spokenLabels(tester), isNot(contains('Cut')));
      expect(spokenLabels(tester), contains(_strings.boldAction));
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
      expect(rig.composer.richText.plain.length, lessThan(18));
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
      expect(focused(), tester.getRect(find.byType(IconButton)));
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

      expect(rig.isOpen, isTrue);
    });

    testWidgets('on the open page Tab walks the page, not the hidden row', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, size: const Size(800, 900));
      await rig.openMore();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(focused().overlaps(tester.getRect(MenuRig.card)), isTrue);
      expect(
        focused(),
        isNot(tester.getRect(MenuRig.item(SelectionMenuItemKind.copy))),
      );
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

    testWidgets('with the More page open Back closes the whole menu', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester);
      await rig.openMore();
      expect(rig.isOpen, isTrue);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await rig.settle();

      expect(MenuRig.card, findsNothing);
      expect(rig.composer.hasFocus, isTrue);
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

    testWidgets('the hook closes the whole menu from the More page', (
      tester,
    ) async {
      ValueGetter<Future<bool>>? onBack;
      final rig = await MenuRig.show(
        tester,
        spec: ComposerSpec(
          backPriority: (callback) {
            onBack = callback;
            return () {};
          },
        ),
      );
      await rig.openMore();

      expect(await onBack!(), isTrue);
      await rig.settle();

      expect(MenuRig.card, findsNothing);
    });
  });

  group('right to left', () {
    testWidgets('the More button is first and the row keeps its start edge', (
      tester,
    ) async {
      final rig = await MenuRig.show(tester, textDirection: TextDirection.rtl);

      final card = tester.getRect(MenuRig.card);
      expect(tester.getRect(MenuRig.more).left, card.left);
      // Its 4 dp of padding are at the card's end, which is the left here.
      expect(tester.getRect(find.byType(IconButton)).left, card.left + 4);
      expect(
        tester.getRect(MenuRig.item(SelectionMenuItemKind.cut)).right,
        card.right,
      );

      await rig.openMore();
      final back = tester.getRect(MenuRig.back);
      // The label starts 54 dp from the row's start, which is its right edge.
      final label = tester.getRect(find.text(_strings.backAction));
      expect(back.right - label.right, 54);
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

  group('with a mouse on a desktop', () {
    final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

    Future<ComposerController> pumpField(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(800, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final composer = ComposerController();
      addTearDown(composer.dispose);
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: composer,
            spec: ComposerSpec(),
            shortcuts: const ComposerShortcutPolicy.desktop().shortcuts,
          ),
        ),
      );
      composer
        ..requestFocus()
        ..restore(long, selection: const TextSelection.collapsed(offset: 0));
      await tester.pump();
      return composer;
    }

    Offset pointOnWord(WidgetTester tester, int offset) {
      final editable = tester.state<ExtendedEditableTextState>(
        find.byType(ExtendedEditableText),
      );
      final render = editable.renderEditable;
      final local = render.getLocalRectForCaret(TextPosition(offset: offset));
      return render.localToGlobal(local.center);
    }

    testWidgets('a right click opens the pointer menu, not the card', (
      tester,
    ) async {
      await pumpField(tester);
      final at = pointOnWord(tester, 5);

      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(MenuRig.card, findsNothing);
      expect(find.byKey(const PointerMenuPanelKey(0)), findsOneWidget);
    }, variant: desktop);

    testWidgets('under the mobile menu policy a right click still opens the '
        'card at the selection', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final composer = ComposerController();
      addTearDown(composer.dispose);
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: composer,
            spec: ComposerSpec(),
            menuPolicy: const ComposerMenuPolicy.mobile(),
            shortcuts: const ComposerShortcutPolicy.desktop().shortcuts,
          ),
        ),
      );
      composer
        ..requestFocus()
        ..restore(long, selection: const TextSelection.collapsed(offset: 0));
      await tester.pump();

      final gesture = await tester.startGesture(
        pointOnWord(tester, 5),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(MenuRig.card, findsOneWidget);
      expect(find.byKey(const PointerMenuPanelKey(0)), findsNothing);
    }, variant: desktop);

    testWidgets('a left click does not open it', (tester) async {
      await pumpField(tester);
      final at = pointOnWord(tester, 5);

      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(MenuRig.card, findsNothing);
    }, variant: desktop);

    testWidgets('a mouse double-click selects the word and shows no menu', (
      tester,
    ) async {
      final composer = await pumpField(tester);
      final at = pointOnWord(tester, 5);

      for (var i = 0; i < 2; i++) {
        final gesture = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(composer.selection.isCollapsed, isFalse);
      expect(MenuRig.card, findsNothing);
    }, variant: desktop);
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
