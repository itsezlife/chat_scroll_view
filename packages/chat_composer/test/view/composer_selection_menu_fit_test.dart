/// How the composer's selection menu fits its labels, by the rule of Telegram's
/// floating toolbar: the main row and the More page are as wide as their
/// labels need, and no label is ellipsized or cut where the screen has the room.
///
/// **Seam:** a `ComposerView` with the menu showing over a selection, in real
/// layout, read through the laid-out paragraphs and rects. The test font draws
/// every glyph as a square of the font size, so the widths are far above a real
/// font's and the screens here are sized to fit the widest label; the rule
/// being tested is the same at any font. English and Russian strings, text
/// scale 1.0 and 1.3, both directions.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/selection_menu_harness.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.hasStrings'
              ? <String, Object?>{'value': true}
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<MenuRig> show(
    WidgetTester tester, {
    required ChromeStrings strings,
    required double scale,
    required Size size,
    TextDirection direction = TextDirection.ltr,
    ComposerSpec? spec,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    return MenuRig.show(
      tester,
      size: size,
      strings: strings,
      textDirection: direction,
      clipboard: FakeRichClipboard(),
      spec: spec,
      // Every row on the page, the greyed ones too: the most there is to fit.
      menuPolicy: const ComposerMenuPolicy.mobile(
        unavailableActions: ComposerUnavailableActions.disable,
      ),
    );
  }

  // Every label the page in view draws, as a paragraph: a row's text, Back, a
  // list marker. The other page is mounted but out of sight.
  List<RenderParagraph> paragraphs(WidgetTester tester) {
    final open = MenuRig.back.hitTestable().evaluate().isNotEmpty;
    final page = find.descendant(
      of: MenuRig.card,
      matching: find.byType(
        open ? SelectionMenuMorePage : SelectionMenuRootPage,
      ),
    );
    return [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: page, matching: find.byType(Text)),
      ))
        tester.renderObject<RenderParagraph>(find.byWidget(text)),
    ];
  }

  void expectNoneCut(WidgetTester tester, {String reason = ''}) {
    final card = tester.getRect(MenuRig.card);
    for (final paragraph in paragraphs(tester)) {
      final label = paragraph.text.toPlainText();
      expect(paragraph.didExceedMaxLines, isFalse, reason: '$label $reason');
      final rect = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        Offset.zero & paragraph.size,
      );
      expect(rect.left, greaterThanOrEqualTo(card.left - 0.5), reason: label);
      expect(rect.right, lessThanOrEqualTo(card.right + 0.5), reason: label);
    }
  }

  final strings = {
    'English': ChromeStringsPresets.english,
    'Russian': ChromeStringsPresets.russian,
  };

  for (final MapEntry(key: language, value: texts) in strings.entries) {
    for (final scale in [1.0, 1.3]) {
      for (final direction in TextDirection.values) {
        final name = '$language, scale $scale, ${direction.name}';

        testWidgets('the More page shows every label in full: $name', (
          tester,
        ) async {
          // 28 characters of the widest Russian label, 18 dp each side, at the
          // test font's 14 dp and the scale, and the 16 dp margins.
          final width = 28 * 14 * scale + 36 + 32 + 20;
          final rig = await show(
            tester,
            strings: texts,
            scale: scale,
            size: Size(width, 700),
            direction: direction,
          );
          await rig.openMore();

          expectNoneCut(tester, reason: name);
          final card = tester.getRect(MenuRig.card);
          expect(card.left, greaterThanOrEqualTo(16));
          expect(card.right, lessThanOrEqualTo(width - 16));
          // Ten formatting rows and the overflowed clipboard ones: four rows,
          // the peek of a fifth and the Back row.
          expect(card.height, 264);

          // Down the list to the last row: none is cut on the way either.
          final list = find.descendant(
            of: MenuRig.card,
            matching: find.byType(ListView),
          );
          for (var i = 0; i < 4; i++) {
            await tester.drag(list, const Offset(0, -150));
            await tester.pump();
            expectNoneCut(tester, reason: '$name, scrolled $i');
          }
        });

        testWidgets('the main row holds Cut, Copy and Paste and the More '
            'button without cutting a label: $name', (tester) async {
          final width = 520.0 * scale;
          final rig = await show(
            tester,
            strings: texts,
            scale: scale,
            size: Size(width, 700),
            direction: direction,
          );

          expectNoneCut(tester, reason: name);
          expect(tester.getSize(MenuRig.more), const Size(56, 48));
          expect(tester.getSize(MenuRig.card).height, 48);
          // Whatever the language and scale leave on the row is 48 tall, and
          // Cut, the first, is always there.
          expect(
            find.descendant(
              of: MenuRig.card,
              matching: find.byType(SelectionMenuButton),
            ),
            findsWidgets,
          );
          for (final button in tester.widgetList<SelectionMenuButton>(
            find.byType(SelectionMenuButton),
          )) {
            expect(
              tester.getSize(find.byWidget(button)).height,
              48,
              reason: button.label,
            );
          }
          expect(MenuRig.item(SelectionMenuItemKind.cut), findsOneWidget);
          expect(rig.isOpen, isFalse);
        });
      }
    }
  }

  testWidgets('the screenshot\'s English row: Cut, Copy, Paste and a kebab, '
      'with 24 dp at the first button\'s start', (tester) async {
    await show(
      tester,
      strings: ChromeStringsPresets.english,
      scale: 1,
      size: const Size(400, 700),
    );

    for (final kind in [
      SelectionMenuItemKind.cut,
      SelectionMenuItemKind.copy,
      SelectionMenuItemKind.paste,
    ]) {
      expect(MenuRig.item(kind), findsOneWidget, reason: '$kind');
    }
    expect(MenuRig.more, findsOneWidget);
    final cut = tester.getRect(MenuRig.item(SelectionMenuItemKind.cut));
    final label = tester.getRect(find.text('Cut'));
    expect(label.left - cut.left, 24);
    expectNoneCut(tester);
  });

  testWidgets('the screenshot\'s Russian page: every label of "Вставить без '
      'форматирования" to "Спойлер" in full', (tester) async {
    final rig = await show(
      tester,
      strings: ChromeStringsPresets.russian,
      scale: 1,
      size: const Size(560, 700),
    );
    await rig.openMore();

    final seen = <String>{};
    final list = find.descendant(
      of: MenuRig.card,
      matching: find.byType(ListView),
    );
    // Down the list a row at a time: every label that comes into view is
    // whole, and the ones the screenshot had cut are among them.
    for (var i = 0; i < 16; i++) {
      for (final paragraph in paragraphs(tester)) {
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: paragraph.text.toPlainText(),
        );
        seen.add(paragraph.text.toPlainText());
      }
      await tester.drag(list, const Offset(0, -42));
      await tester.pump();
    }
    expect(
      seen,
      containsAll([
        ChromeStringsPresets.russian.composer.pastePlainAction,
        ChromeStringsPresets.russian.formatting.boldAction,
        ChromeStringsPresets.russian.formatting.underlineAction,
        ChromeStringsPresets.russian.formatting.monoAction,
        ChromeStringsPresets.russian.formatting.spoilerAction,
        ChromeStringsPresets.russian.formatting.clearFormattingAction,
      ]),
    );
    expectNoneCut(tester);
    // At the end the last row rests 2 dp above the list's end, whole.
    final box = tester.getRect(list);
    final last = tester.getRect(
      MenuRig.item(SelectionMenuItemKind.clearFormatting),
    );
    expect(last.bottom, closeTo(box.bottom - 2, 0.5));
    expect(last.top, greaterThanOrEqualTo(box.top));
  });

  testWidgets('a label wider than the screen less 32 dp is the one thing '
      'that is cut, and the card keeps the margins', (tester) async {
    final rig = await show(
      tester,
      strings: ChromeStringsPresets.russian,
      scale: 1,
      size: const Size(300, 700),
    );
    await rig.openMore();

    final card = tester.getRect(MenuRig.card);
    expect(card.width, 300 - 32);
    expect(card.left, 16);
    expect(card.right, 300 - 16);
    final cut = paragraphs(tester).where((p) => p.didExceedMaxLines);
    expect(cut, isNotEmpty, reason: 'the 28-glyph label cannot fit 268 dp');
  });

  testWidgets('the Back row is whole on a page of short labels', (
    tester,
  ) async {
    // The reference clips its Back label there; the page is as wide as it.
    final rig = await show(
      tester,
      strings: ChromeStringsPresets.russian,
      scale: 1,
      size: const Size(520, 700),
      spec: ComposerSpec(formatting: const {ComposerFormattingOption.bold}),
    );
    await rig.openMore();

    final back = find.descendant(
      of: find.byKey(SelectionMenuMorePage.backKey),
      matching: find.byType(Text),
    );
    expect(
      tester.renderObject<RenderParagraph>(back).didExceedMaxLines,
      isFalse,
    );
    expectNoneCut(tester);
  });
}
