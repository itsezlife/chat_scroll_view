/// What a copy confirms and what it leaves selected, per platform family:
///
/// * Desktop: no copy of text or of messages shows a toast, and none clears
///   the selection. Only a click on code does.
/// * Mobile: every copy shows the "copied" bulletin, and a copy of selected
///   messages or of selected text ends the selection.
///
/// **Seam:** the whole screen on a given platform, driven by real key events
/// and taps; the clipboard is the services' `FakeRichClipboard`, read back, so
/// a test also proves the content did not change with the feedback. A real
/// device or desktop cannot be run here.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/showcase_bodies.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy_feedback.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_soft_keyboard.dart';
import '../support/test_services.dart';

class _TwoMessages extends ChatDataSource {
  _TwoMessages() {
    upsertMessages(<IChatMessage>[
      for (final (id, text) in [(1, 'first'), (2, 'second')])
        UserChatMessage(
          id: id,
          sender: 'User',
          createdAt: DateTime(2026, 1, 1, 12, id),
          updatedAt: DateTime(2026, 1, 1, 12, id),
          content: text,
        ),
    ]);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;
  late FakeSoftKeyboard keyboard;
  late GeneratedChatDataSource source;

  setUp(() => keyboard = FakeSoftKeyboard());
  tearDown(() => keyboard.dispose());

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void screenTest(
    String name,
    TargetPlatform platform,
    Future<void> Function(WidgetTester, ChatSelectionController) body, {
    int androidSdk = 34,
  }) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    const system = MethodChannel('chat_scroll_view_example/system');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      system,
      (call) async => {'sdkInt': androidSdk, 'oneUi40': false},
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        system,
        null,
      ),
    );
    try {
      // Tall enough that every showcase body is laid out, the early ones
      // these tests select included.
      tester.view
        ..physicalSize = const Size(900, 12000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      source = GeneratedChatDataSource(
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

  // The selection bar slides in from above the screen, over some frames.
  Future<void> slideBarIn(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // The selection bar's Copy.
  Future<void> tapBarCopy(WidgetTester tester) async {
    await slideBarIn(tester);
    await tester.tap(find.byTooltip('Копировать'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  // A mouse drag over "hanks" in message 8: "Thanks @Ann and @bob, ...".
  Future<void> dragSelectText(
    WidgetTester tester,
    ChatSelectionController selection,
  ) async {
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
  }

  // Any of the copy bulletins: message, text, code or link.
  final copied = find.textContaining('скопирован');

  Future<void> selectTwoMessages(
    WidgetTester tester,
    ChatSelectionController selection,
  ) async {
    selection
      ..startSelection(8)
      ..toggle(9);
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('desktop: a copy is silent and keeps the selection', () {
    screenTest('Cmd+C on selected messages', TargetPlatform.macOS, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await copyShortcut(tester);

      expect((await clipboard().read())?.plain, contains('Thanks @Ann'));
      expect(copied, findsNothing);
      expect(selection.isSelectionMode, isTrue);
      expect(selection.selectedIds, {8, 9});
    });

    screenTest('Ctrl+C on selected messages', TargetPlatform.windows, (
      tester,
      selection,
    ) async {
      selection.startSelection(8);
      await tester.pump(const Duration(milliseconds: 100));

      await copyShortcut(
        tester,
        modifier: LogicalKeyboardKey.controlLeft,
        platform: 'windows',
      );

      expect(
        (await clipboard().read())?.plain,
        'Thanks @Ann and @bob, see #release for notes',
      );
      expect(copied, findsNothing);
      expect(selection.isSelectionMode, isTrue);
    });

    screenTest('the selection bar Copy', TargetPlatform.macOS, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await tapBarCopy(tester);

      expect((await clipboard().read())?.plain, contains('Thanks @Ann'));
      expect(copied, findsNothing);
      expect(selection.isSelectionMode, isTrue);
    });

    screenTest('Cmd+C on selected text', TargetPlatform.macOS, (
      tester,
      selection,
    ) async {
      await dragSelectText(tester, selection);

      await copyShortcut(tester);

      expect((await clipboard().read())?.plain, 'hanks');
      expect(copied, findsNothing);
      expect(selection.isTextSelectionActive, isTrue);
    });
  });

  group('mobile: a copy confirms and ends the selection', () {
    screenTest('the selection bar Copy on iOS', TargetPlatform.iOS, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await tapBarCopy(tester);

      expect((await clipboard().read())?.plain, contains('Thanks @Ann'));
      expect(copied, findsOneWidget);
      expect(selection.isSelectionMode, isFalse);
    });

    screenTest('a shortcut on selected messages on iOS', TargetPlatform.iOS, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await copyShortcut(tester, platform: 'ios');

      expect((await clipboard().read())?.plain, contains('Thanks @Ann'));
      expect(copied, findsOneWidget);
      expect(selection.isSelectionMode, isFalse);
    });

    screenTest(
      'the selection bar Copy of selected text on iOS',
      TargetPlatform.iOS,
      (tester, selection) async {
        selection.startSelection(8);
        await tester.pump(const Duration(milliseconds: 100));
        await slideBarIn(tester);
        await tester.tap(find.byTooltip('Выделить текст'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(selection.isTextSelectionActive, isTrue);

        await tapBarCopy(tester);
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          (await clipboard().read())?.plain,
          'Thanks @Ann and @bob, see #release for notes',
        );
        expect(copied, findsOneWidget);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.isSelectionMode, isFalse);
      },
    );

    // The system confirms a copy on Android
    // (API 32+, its clipboard-toast rule): the app adds
    // none, but the selection still ends.
    screenTest('the selection bar Copy on Android', TargetPlatform.android, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await tapBarCopy(tester);

      expect((await clipboard().read())?.plain, contains('Thanks @Ann'));
      expect(copied, findsNothing);
      expect(selection.isSelectionMode, isFalse);
    });

    // Below API 31 the system shows nothing: the app confirms the copy.
    screenTest('the selection bar Copy on Android 11', TargetPlatform.android, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await tapBarCopy(tester);

      expect(copied, findsOneWidget);
      expect(selection.isSelectionMode, isFalse);
    }, androidSdk: 30);
  });

  group('the message menu', () {
    // A right click on message 8 while 8 and 9 are selected: the desktop
    // menu's bulk rows.
    Future<void> copyFromMenu(
      WidgetTester tester,
      ChatSelectionController selection,
    ) async {
      final at = selection.messageSurfaceGlobal(8)!.rect.center;
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.down(at, buttons: kSecondaryButton),
      );
      await tester.sendEventToBinding(mouse.up());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Copy Selected as Text'));
      await tester.pump(const Duration(milliseconds: 100));
    }

    screenTest('desktop: Copy of the selected messages', TargetPlatform.macOS, (
      tester,
      selection,
    ) async {
      await selectTwoMessages(tester, selection);

      await copyFromMenu(tester, selection);

      expect((await clipboard().read())?.plain, contains('Thanks @Ann'));
      expect(copied, findsNothing);
      expect(selection.isSelectionMode, isTrue);
    });
  });

  // The menu opened over selected messages is out of reach of
  // a gesture here (the screen opens none in selection mode), so the session
  // is driven directly, under each policy.
  group('the menu session over selected messages', () {
    Future<(ChatSelectionController, List<String>)> copyFromMenu(
      WidgetTester tester,
      ChatSelectionPolicy policy,
      FakeRichClipboard clipboard,
    ) async {
      final dataSource = _TwoMessages();
      final selection = ChatSelectionController(policy: policy);
      addTearDown(dataSource.dispose);
      addTearDown(selection.dispose);
      selection
        ..startSelection(1)
        ..toggle(2);
      final copiedTexts = <String>[];
      final menu = MessageMenu(
        dataSource: dataSource,
        selection: selection,
        clipboard: clipboard,
        actions: MessageMenuActions(
          onDelete: (_) {},
          onEdit: (_) {},
          onCopy: copiedTexts.add,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => menu.present(
                  context,
                  const ChatMessageMenuRequest(
                    messageId: 1,
                    slotGlobal: Rect.fromLTWH(0, 100, 400, 80),
                    tapGlobal: Offset(140, 130),
                    membership: ChatMessageMenuMembership.uponSelected,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Copy Selected as Text'));
      await tester.pump(const Duration(milliseconds: 100));
      return (selection, copiedTexts);
    }

    testWidgets('mobile: the copy ends the selection', (tester) async {
      final clipboard = FakeRichClipboard();

      final (selection, copiedTexts) = await copyFromMenu(
        tester,
        const ChatSelectionPolicy.mobile(),
        clipboard,
      );

      expect((await clipboard.read())?.plain, contains('first'));
      expect(copiedTexts, hasLength(1));
      expect(selection.isSelectionMode, isFalse);
    });

    testWidgets('desktop: the copy keeps the selection', (tester) async {
      final clipboard = FakeRichClipboard();

      final (selection, copiedTexts) = await copyFromMenu(
        tester,
        const ChatSelectionPolicy.desktop(),
        clipboard,
      );

      expect((await clipboard.read())?.plain, contains('first'));
      expect(copiedTexts, hasLength(1));
      expect(selection.isSelectionMode, isTrue);
    });
  });

  group('code', () {
    // A tap on code is confirmed on every platform.
    Future<void> tapCode(
      WidgetTester tester,
      ChatSelectionController selection,
    ) async {
      source.editMessage(source.getMessage(8)! as UserChatMessage, '`snippet`');
      await tester.pump(const Duration(milliseconds: 300));
      final surface = selection.surfaceFor(8)!;
      final at = (surface as RenderBox).localToGlobal(
        surface.localBoxesForRange(0, 0, 3).first.center,
      );
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
    }

    screenTest('is confirmed on desktop', TargetPlatform.macOS, (
      tester,
      selection,
    ) async {
      await tapCode(tester, selection);

      expect((await clipboard().read())?.plain, 'snippet');
      expect(copied, findsOneWidget);
    });

    screenTest('is confirmed on iOS', TargetPlatform.iOS, (
      tester,
      selection,
    ) async {
      await tapCode(tester, selection);

      expect((await clipboard().read())?.plain, 'snippet');
      expect(copied, findsOneWidget);
    });
  });

  group('the rule by kind of copy', () {
    const desktop = ChatSelectionPolicy.desktop();
    const mobile = ChatSelectionPolicy.mobile();

    test('desktop confirms code alone', () {
      final feedback = ChatCopyFeedback.forPolicy(desktop);

      expect(feedback, isA<ChatCopyFeedback$Desktop>());
      expect(
        {
          for (final kind in ChatCopyKind.values)
            kind: feedback.showsToast(kind),
        },
        {
          ChatCopyKind.messages: false,
          ChatCopyKind.textSelection: false,
          ChatCopyKind.link: false,
          ChatCopyKind.code: true,
        },
      );
    });

    test('mobile confirms every kind', () {
      final feedback = ChatCopyFeedback.forPolicy(mobile);

      expect(feedback, isA<ChatCopyFeedback$Mobile>());
      expect([
        for (final kind in ChatCopyKind.values) feedback.showsToast(kind),
      ], everyElement(isTrue));
    });

    test('a mobile system that confirms itself leaves the app silent', () {
      final feedback = ChatCopyFeedback.forPolicy(mobile, systemConfirms: true);

      expect([
        for (final kind in ChatCopyKind.values) feedback.showsToast(kind),
      ], everyElement(isFalse));
    });
    // The app toasts while
    // (SDK < 31 || !built-in toasts) && SDK < 32.
    test('Android confirms by itself only from 12L, or 12 on One UI 4.0', () {
      bool confirms(int sdk, {bool oneUi = false}) =>
          ChatCopyFeedback.androidSystemConfirms(
            sdkInt: sdk,
            hasBuiltInClipboardToasts: oneUi,
          );

      expect(confirms(30), isFalse);
      expect(confirms(30, oneUi: true), isFalse);
      expect(confirms(31), isFalse);
      expect(confirms(31, oneUi: true), isTrue);
      expect(confirms(32), isTrue);
      expect(confirms(34), isTrue);
    });
  });
}
