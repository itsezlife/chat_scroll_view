/// The desktop copy shortcut over the chat screen: with messages selected,
/// Cmd+C (Ctrl+C elsewhere) copies them, wherever the keyboard focus is.
///
/// **Seam:** the whole screen on a desktop platform, driven by real key
/// events; the clipboard is the services' `FakeRichClipboard`, read back.
/// A real desktop cannot be run here, so the key events stand for it.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/showcase_bodies.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_soft_keyboard.dart';
import '../support/test_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;
  late FakeSoftKeyboard keyboard;

  setUp(() => keyboard = FakeSoftKeyboard());
  tearDown(() => keyboard.dispose());

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void desktopTest(
    String name,
    Future<void> Function(WidgetTester, ChatSelectionController) body, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      tester.view
        ..physicalSize = const Size(900, 4000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      final source = GeneratedChatDataSource(
        messageCount: ShowcaseBodies.all.length,
        style: GeneratedMessageStyle.showcase,
      );
      await tester.pumpWidget(
        ChatDemoApp(
          services: services,
          softKeyboard: keyboard,
          chatDataSourceLoader: () async => source,
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final selection = tester
          .widget<ChatScrollView>(find.byType(ChatScrollView))
          .selectionController!;
      await body(tester, selection);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  FakeRichClipboard clipboard() => services.clipboard as FakeRichClipboard;

  Future<void> copyShortcut(
    WidgetTester tester, {
    LogicalKeyboardKey modifier = LogicalKeyboardKey.metaLeft,
    String platform = 'macos',
  }) async {
    await tester.sendKeyDownEvent(modifier, platform: platform);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC, platform: platform);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC, platform: platform);
    await tester.sendKeyUpEvent(modifier, platform: platform);
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('with messages selected', () {
    desktopTest('Cmd+C copies them, when the chat has the focus', (
      tester,
      selection,
    ) async {
      selection
        ..startSelection(8)
        ..toggle(9);
      await tester.pump(const Duration(milliseconds: 100));

      await copyShortcut(tester);

      final copied = await clipboard().read();
      // The desktop client's lines: [time] Name: text, a newline apart.
      expect(
        copied?.plain,
        matches(
          RegExp(
            r'^\[[^\]]+\] [^:\n]+: Thanks @Ann and @bob, see #release for notes\n'
            r'\[[^\]]+\] [^:\n]+: A plain link too: flutter\.dev$',
          ),
        ),
      );
      expect(selection.isSelectionMode, isFalse);
    });

    desktopTest(
      'Ctrl+C copies them on a platform that uses Ctrl',
      (tester, selection) async {
        selection.startSelection(8);
        await tester.pump(const Duration(milliseconds: 100));

        await copyShortcut(
          tester,
          modifier: LogicalKeyboardKey.controlLeft,
          platform: 'windows',
        );

        // One message on the desktop is its text alone.
        expect(
          (await clipboard().read())?.plain,
          'Thanks @Ann and @bob, see #release for notes',
        );
      },
      platform: TargetPlatform.windows,
    );

    desktopTest(
      'Cmd+C copies several in the mobile format on a mobile platform',
      (tester, selection) async {
        selection
          ..startSelection(8)
          ..toggle(9);
        await tester.pump(const Duration(milliseconds: 100));

        await copyShortcut(tester, platform: 'ios');

        // The Android client's: a Name: line, a blank line between messages.
        expect(
          (await clipboard().read())?.plain,
          matches(
            RegExp(
              r'^[^:\n]+:\nThanks @Ann and @bob, see #release for notes\n\n'
              r'([^:\n]+:\n)?A plain link too: flutter\.dev$',
            ),
          ),
        );
      },
      platform: TargetPlatform.iOS,
    );
  });

  group('with no message selected', () {
    desktopTest('Cmd+C copies the selected text of a message', (
      tester,
      selection,
    ) async {
      // Message 8: "Thanks @Ann and @bob, see #release for notes".
      final surface = selection.surfaceFor(8)!;
      Offset on(int from, int to) => (surface as RenderBox).localToGlobal(
        surface.localBoxesForRange(0, from, to).first.center,
      );
      final mouse = await tester.startGesture(
        on(0, 1),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(on(5, 6));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(selection.isTextSelectionActive, isTrue);

      await copyShortcut(tester);

      // Through the host's rich clipboard, not the engine's plain copy.
      expect((await clipboard().read())?.plain, 'hanks');
      expect(selection.isTextSelectionActive, isTrue);
    });

    desktopTest('Cmd+C copies the selected text of the composer', (
      tester,
      selection,
    ) async {
      // The composer's field is a leaf package's type, which a host does
      // not name.
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'ComposerField',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      tester.testTextInput.enterText('draft words');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      await copyShortcut(tester);

      expect((await clipboard().read())?.plain, 'draft words');
      expect(selection.isSelectionMode, isFalse);
    });
  });
}
