import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';
import '../support/simulated_input.dart';

void main() {
  group('ComposerShortcutPolicy', () {
    test('picks the family of the platform', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          ComposerShortcutPolicy.forPlatform(platform),
          isA<ComposerShortcutPolicy$Mobile>(),
        );
      }
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          ComposerShortcutPolicy.forPlatform(platform),
          isA<ComposerShortcutPolicy$Desktop>(),
        );
      }
    });

    test('the web counts as desktop whatever the platform says', () {
      expect(
        ComposerShortcutPolicy.forPlatform(TargetPlatform.android, isWeb: true),
        isA<ComposerShortcutPolicy$Desktop>(),
      );
    });

    test('only the desktop policy binds Enter', () {
      const enter = SingleActivator(LogicalKeyboardKey.enter);

      expect(
        const ComposerShortcutPolicy.desktop().shortcuts[enter],
        isA<SubmitComposerIntent>(),
      );
      expect(
        const ComposerShortcutPolicy.mobile().shortcuts.containsKey(enter),
        isFalse,
      );
    });

    test('both bind Escape to dismissing the header', () {
      const escape = SingleActivator(LogicalKeyboardKey.escape);

      expect(
        const ComposerShortcutPolicy.desktop().shortcuts[escape],
        isA<DismissComposerHeaderIntent>(),
      );
      expect(
        const ComposerShortcutPolicy.mobile().shortcuts[escape],
        isA<DismissComposerHeaderIntent>(),
      );
    });
  });

  group('ComposerView shortcuts', () {
    late ComposerController controller;
    var sends = 0;
    var dismisses = 0;

    setUp(() {
      controller = ComposerController();
      sends = 0;
      dismisses = 0;
    });
    tearDown(() => controller.dispose());

    ComposerSpec spec({bool busy = false, bool withHeader = false}) =>
        ComposerSpec(
          busy: busy,
          header: withHeader
              ? ComposerHeader.edit(preview: 'x', onDismiss: () => dismisses++)
              : null,
          actions: [
            ActionDescriptor(
              id: 'send',
              icon: ChromeIconId.send,
              semanticLabel: 'Send',
              primary: true,
              onTap: () => sends++,
            ),
          ],
        );

    Future<void> show(
      WidgetTester tester,
      ComposerSpec spec, {
      ComposerShortcutPolicy policy = const ComposerShortcutPolicy.desktop(),
    }) async {
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: controller,
            spec: spec,
            shortcuts: policy.shortcuts,
          ),
        ),
      );
      controller.requestFocus();
      await tester.pump();
    }

    testWidgets('Enter invokes the primary action', (tester) async {
      await show(tester, spec());

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(sends, 1);
    });

    testWidgets('Shift+Enter does not submit', (tester) async {
      await show(tester, spec());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(sends, 0);
    });

    testWidgets('Enter does nothing while busy', (tester) async {
      await show(tester, spec(busy: true));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(sends, 0);
    });

    testWidgets('Enter is left to the input method while it composes', (
      tester,
    ) async {
      await show(tester, spec());
      controller.text.compose('ni', const TextRange(start: 0, end: 2));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(sends, 0);
    });

    testWidgets('the mobile policy leaves Enter alone', (tester) async {
      await show(tester, spec(), policy: const ComposerShortcutPolicy.mobile());

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(sends, 0);
    });

    testWidgets('Escape dismisses the header', (tester) async {
      await show(tester, spec(withHeader: true));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(dismisses, 1);
    });

    testWidgets('Escape does nothing without a header', (tester) async {
      await show(tester, spec());

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(dismisses, 0);
    });

    testWidgets('Enter or Space activates a focused action button', (
      tester,
    ) async {
      await show(tester, spec());
      // Traverse from the field to the action, then press Space.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      expect(sends, 1);
    });
  });
}
