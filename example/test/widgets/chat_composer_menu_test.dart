/// The demo composer's selection menu: its options, labels, link prompt and
/// back priority, wired by the host.
///
/// **Seam:** the chat's input set under the app's scopes (`InputRig`), driven
/// by touches on the field, the labels of `demoChromeStrings` and the system
/// back button.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackBinding, ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

final _strings = demoChromeStrings.formatting;

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

/// Types [text], selects `[start, end)` and brings the menu up with a long
/// press on the field, as a touch platform does.
Future<void> _selectAndShowMenu(
  WidgetTester tester,
  InputRig rig,
  String text,
  TextSelection selection,
) async {
  await rig.typeInField(tester, text);
  rig.set.composer.select(selection);
  await tester.pump();
  await tester.longPress(rig.field);
  await tester.pumpAndSettle();
}

/// Taps the More page's item labelled [label], scrolling it into view.
Future<void> _tapPageItem(WidgetTester tester, String label) async {
  await _openMore(tester);
  final item = find.text(label);
  if (item.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      item,
      42,
      scrollable: find.byType(Scrollable).last,
    );
    // Partly under the page's edge is visible but not yet tappable.
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
  }
  await tester.tap(item.hitTestable());
  await tester.pumpAndSettle();
}

/// Opens the menu's More page, where the formatting items are.
Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('selection_menu_more')));
  await tester.pumpAndSettle();
}

void main() {
  group('the selection menu', () {
    testWidgets('bolds the selection', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );

      await _selectAndShowMenu(
        tester,
        rig,
        'one two three',
        const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await _tapPageItem(tester, _strings.boldAction);

      expect(
        rig.set.composer.richText,
        RichText('one two three', const [Entity(4, 3, EntityKind.bold)]),
      );
    });

    testWidgets('creates a link from the dialog, prefilled from the clipboard '
        'and applied trimmed', (tester) async {
      final services = await _services(tester);
      await services.clipboard.write(
        const RichText.plain('  https://example.com/page  '),
      );
      final rig = await InputRig.pump(tester, services: services);

      await _selectAndShowMenu(
        tester,
        rig,
        'one two three',
        const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await _tapPageItem(tester, _strings.createLinkAction);

      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        '  https://example.com/page  ',
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        rig.set.composer.richText,
        RichText('one two three', const [
          Entity(4, 3, EntityKind.link('https://example.com/page')),
        ]),
      );
    });

    group('system back', () {
      tearDown(ChatPreImeBackBinding.debugReset);

      Future<InputRig> openOverflow(WidgetTester tester) async {
        final rig = await InputRig.pump(
          tester,
          services: await _services(tester),
        );
        await _selectAndShowMenu(
          tester,
          rig,
          'one two three',
          const TextSelection(baseOffset: 4, extentOffset: 7),
        );
        await _openMore(tester);
        expect(find.text(_strings.boldAction), findsOneWidget);
        return rig;
      }

      Future<void> back(WidgetTester tester) async {
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
      }

      testWidgets('closes the whole menu from the More page', (tester) async {
        await openOverflow(tester);

        await back(tester);

        expect(find.text('Copy'), findsNothing);
        expect(find.text(_strings.boldAction), findsNothing);
      });

      testWidgets('is claimed ahead of the soft keyboard while the menu is up '
          'and given back with it', (tester) async {
        await openOverflow(tester);

        expect(await ChatPreImeBackClaim.handleNativeBack(), isTrue);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('Copy'), findsNothing);

        expect(await ChatPreImeBackClaim.handleNativeBack(), isFalse);
      });
    });
  });
}
