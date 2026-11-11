/// On a desktop the keys have an owner from the moment a chat opens: the
/// composer's field, which hands the scroll keys it cannot use to the panel
/// under the mouse or else the chat; the chat when the field is left; the
/// panel once pressed.
///
/// **Seam:** the whole app on macOS, opening the chat from the chat list as
/// a user does, driven by real key events and one mouse; observed through
/// the chat controller's scroll events, the composer's caret and focus, the
/// catalogue's offset and the clipboard.
library;

import 'package:chat_composer/chat_composer.dart'
    show ComposerController, ComposerView;
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

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
  void macTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          tester.view
            ..physicalSize = const Size(1000, 800)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          services = (await tester.runAsync(createTestServices))!;
          addTearDown(services.dispose);
          await tester.pumpWidget(
            ChatDemoApp(
              services: services,
              softKeyboard: keyboard,
              start: DemoStart.chatList,
              chatDataSourceLoader: () async =>
                  GeneratedChatDataSource(messageCount: 400),
            ),
          );
          await tester.pump();
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Opens the first chat of the list and returns its scrolls by key.
  Future<List<double>> openChat(WidgetTester tester) async {
    await tester.tap(find.text('Design review'));
    await settle(tester);
    final controller = tester
        .widget<ChatScrollView>(find.byType(ChatScrollView))
        .controller;
    final scrolls = <double>[];
    controller.addScrollListener((event) {
      if (event case ChatProgrammaticScroll(:final delta)) scrolls.add(delta);
    });
    return scrolls;
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key, platform: 'macos');
    await tester.pump(const Duration(milliseconds: 50));
  }

  ComposerController composer(WidgetTester tester) =>
      tester.widget<ComposerView>(find.byType(ComposerView)).controller;

  PanelCatalogController catalogue(WidgetTester tester) => tester
      .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
      .controller;

  // Puts the mouse over the panel's catalogue, the panel opened by hovering
  // its button, once the catalogue has more than a screen of rows.
  Future<TestGesture> hoverPanel(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(4, 4));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey(ChatComposerActions.panel))),
    );
    await settle(tester);
    for (var i = 0; i < 100 && catalogue(tester).maxScrollExtent < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await mouse.moveTo(tester.getCenter(find.byType(PanelCatalogViewport)));
    await tester.pump();
    return mouse;
  }

  macTest('the scroll keys scroll the chat as soon as it opens, and again '
      'after it is closed and opened', (tester) async {
    for (var round = 0; round < 2; round++) {
      final scrolls = await openChat(tester);

      await key(tester, LogicalKeyboardKey.pageUp);
      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.pageDown);
      await key(tester, LogicalKeyboardKey.arrowDown);

      expect(scrolls, hasLength(4), reason: 'round $round');
      expect(scrolls[0], greaterThan(0), reason: 'Page Up: older');
      expect(scrolls[1], greaterThan(0), reason: 'Up: older');
      expect(scrolls[2], lessThan(0), reason: 'Page Down: newer');
      expect(scrolls[3], lessThan(0), reason: 'Down: newer');

      await Navigator.maybePop(tester.element(find.byType(ChatScrollView)));
      await settle(tester);
      expect(find.byType(ChatScrollView), findsNothing);
    }
  });

  // Home and End as a MacBook sends them: Fn held with the left and right
  // arrows, which arrive as the Home and End keys.
  Future<void> fnKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.fn, platform: 'macos');
    await tester.sendKeyEvent(key, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.fn, platform: 'macos');
    await tester.pump(const Duration(milliseconds: 50));
  }

  macTest('Home goes to the newest message and End to the oldest, as before '
      'the router: from the field, empty or with a draft, a field left and a '
      'selection, Fn held or not', (tester) async {
    await openChat(tester);
    final view = tester.widget<ChatScrollView>(find.byType(ChatScrollView));
    final controller = view.controller;
    final jumps = <int>[];
    controller.addScrollListener((event) {
      if (event case ChatProgrammaticJump(:final targetId)) {
        jumps.add(targetId);
      }
    });
    final oldest = controller.oldestKnownId!;
    final newest = controller.newestKnownId!;
    expect(oldest, isNot(newest));

    Future<void> both({required String reason, bool fn = false}) async {
      jumps.clear();
      await (fn ? fnKey : key)(tester, LogicalKeyboardKey.end);
      await settle(tester);
      expect(controller.isAtTail.value, isFalse, reason: '$reason: End');
      await (fn ? fnKey : key)(tester, LogicalKeyboardKey.home);
      await settle(tester);
      expect(controller.isAtTail.value, isTrue, reason: '$reason: Home');
      expect(jumps, [oldest, newest], reason: reason);
    }

    expect(composer(tester).focusNode.hasFocus, isTrue);
    await both(reason: 'empty field');
    await both(reason: 'empty field, Fn', fn: true);

    // A draft in the field: on a Mac, Home and End move no caret in a
    // text, so they still go to the chat.
    composer(tester).insertText('draft');
    await tester.pump();
    await both(reason: 'draft', fn: true);
    expect(composer(tester).text.text, 'draft');
    composer(tester).clear();
    await tester.pump();

    composer(tester).focusNode.unfocus();
    await tester.pump();
    await tester.pump();
    await both(reason: 'field left');

    view.selectionController!.startSelection(newest);
    await settle(tester);
    await both(reason: 'selection');
  });

  macTest('a click in the history, on a message or between them, keeps the '
      'field focused: typing goes on into it', (tester) async {
    await openChat(tester);
    expect(composer(tester).focusNode.hasFocus, isTrue);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(4, 4));
    addTearDown(mouse.removePointer);
    Future<void> click(Offset at) async {
      await mouse.moveTo(at);
      await mouse.down(at);
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    final history = tester.getRect(find.byType(ChatScrollView));
    // Between messages, at the history's left edge.
    await click(Offset(history.left + 4, history.center.dy));
    expect(composer(tester).focusNode.hasFocus, isTrue, reason: 'blank');
    // On a message bubble.
    await click(tester.getCenter(find.byType(DemoMessageBubble).last));
    expect(composer(tester).focusNode.hasFocus, isTrue, reason: 'message');

    tester.testTextInput.enterText('typed on');
    await tester.pump();
    expect(composer(tester).text.text, 'typed on');
  });

  macTest('the field keeps the keys that edit its text, and hands the chat '
      'those it cannot use', (tester) async {
    final scrolls = await openChat(tester);
    final field = composer(tester);
    expect(field.focusNode.hasFocus, isTrue, reason: 'opened focused');
    field.insertText('one');
    await tester.pump();
    expect(field.selection.baseOffset, 3);

    // The caret can go back: the field's.
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(field.selection.baseOffset, 0);
    expect(scrolls, isEmpty);
    // At the start, up is the chat's.
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(scrolls, hasLength(1));
    // Down takes the caret to the end, then is the chat's.
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(field.selection.baseOffset, 3);
    expect(scrolls, hasLength(1));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(scrolls, hasLength(2));
    // The page keys always are the chat's.
    await key(tester, LogicalKeyboardKey.pageUp);
    expect(scrolls, hasLength(3));
    expect(field.focusNode.hasFocus, isTrue);
  });

  macTest('with the field focused, the panel under the mouse takes the '
      'scroll keys', (tester) async {
    final scrolls = await openChat(tester);
    await hoverPanel(tester);
    expect(composer(tester).focusNode.hasFocus, isTrue);
    expect(catalogue(tester).maxScrollExtent, greaterThan(200));

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(catalogue(tester).offset, 60);
    await key(tester, LogicalKeyboardKey.end);
    expect(catalogue(tester).offset, catalogue(tester).maxScrollExtent);
    await key(tester, LogicalKeyboardKey.home);
    expect(catalogue(tester).offset, 0);
    expect(scrolls, isEmpty);
    expect(composer(tester).focusNode.hasFocus, isTrue);
  });

  macTest('a field left with nothing else focused leaves the keys with the '
      'chat', (tester) async {
    final scrolls = await openChat(tester);
    composer(tester).focusNode.unfocus();
    await tester.pump();
    await tester.pump();

    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.pageUp);

    expect(scrolls, hasLength(2));
  });

  macTest('a message selection holds the keys for the chat, and the field '
      'has them back once it ends', (tester) async {
    final scrolls = await openChat(tester);
    final view = tester.widget<ChatScrollView>(find.byType(ChatScrollView));
    final selection = view.selectionController!;
    selection.startSelection(view.controller.newestKnownId!);
    await settle(tester);
    expect(composer(tester).focusNode.hasFocus, isFalse);

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(scrolls, hasLength(1));

    selection.clear();
    await settle(tester);
    expect(composer(tester).focusNode.hasFocus, isTrue);
  });

  macTest('with messages selected, Cmd+C copies them and Escape clears '
      'them while the panel holds the keys', (tester) async {
    await openChat(tester);
    final view = tester.widget<ChatScrollView>(find.byType(ChatScrollView));
    final selection = view.selectionController!;
    selection.startSelection(view.controller.newestKnownId!);
    await tester.pump(const Duration(milliseconds: 100));
    // The catalogue holds the keys: the mouse over it, and its focus (as a
    // press on it gives it when no field has the focus).
    await hoverPanel(tester);
    tester
        .widget<Focus>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Focus &&
                widget.focusNode?.debugLabel == 'CatalogKeyboardFocus',
          ),
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'CatalogKeyboardFocus',
    );

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      (await (services.clipboard as FakeRichClipboard).read())?.plain,
      isNotEmpty,
    );

    await key(tester, LogicalKeyboardKey.escape);
    expect(selection.isSelectionMode, isFalse);
  });
}
