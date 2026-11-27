/// A message the host's `canCopy` refuses is copied by no path of the facade.
///
/// **Seam:** [ChatSelectionController] with a `canCopy` hook, driven by
/// `copyTextSelection`, `handleInlineHit`, `refusesCopy` and a mounted
/// [ChatMarkdownBody]; observed through the clipboard, the interactions and
/// the diagnostics events.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart'
    show ChatEventCategory, ChatEventLevel;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart' show MarkdownThemeData;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> clipboard;
  late List<ChatSelectionInteraction> interactions;
  late Set<int> refused;
  late RecordingDiagnostics diagnostics;

  ChatSelectionController facade({
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
    bool copyCodeOnClick = true,
  }) {
    final selection = ChatSelectionController(
      policy: policy,
      copyCodeOnClick: copyCodeOnClick,
      canCopy: (id) => !refused.contains(id),
      chatId: 'chat-1',
    )..addInteractionListener(interactions.add);
    addTearDown(selection.dispose);
    return selection;
  }

  setUp(() {
    clipboard = [];
    interactions = [];
    refused = {};
    diagnostics = RecordingDiagnostics.install();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  void expectRefusedEvent(int messageId, String path) {
    final event = diagnostics.whereOp(ChatSelectionOp.copyRefused).single;
    expect(event.category, ChatEventCategory.capabilities);
    expect(event.level, ChatEventLevel.info);
    expect(event.correlation.chatId, 'chat-1');
    expect(event.correlation.scrollId, '$messageId');
    expect(event.fields.keys, ['path']);
    // An enum field is logged by its name.
    expect((event.fields['path']! as Enum).name, path);
  }

  test('every message may be copied without a hook', () {
    final selection = ChatSelectionController();
    addTearDown(selection.dispose);
    expect(selection.isCopyAllowed(1), isTrue);
    expect(selection.refusesCopy([1, 2]), isFalse);
  });

  group('a refused message', () {
    test('refuses its text selection copy, once, keeping the range', () async {
      refused.add(1);
      final selection = facade()
        ..putBody(1, Markdown.fromString('Secret text'))
        ..startSelection(1);
      expect(selection.enterTextSelection(1), isTrue);

      expect(await selection.copyTextSelection(), isFalse);

      expect(clipboard, isEmpty);
      expect(interactions, [
        const ChatSelectionInteraction.copyRefused(
          messageId: 1,
          origin: ChatCopyOrigin.textSelection,
        ),
      ]);
      expect(selection.isTextSelectionActive, isTrue);
      expectRefusedEvent(1, 'textSelection');
      // No user content in the event.
      expect(
        diagnostics.events.single.fields.values,
        isNot(contains('Secret')),
      );
    });

    test('refuses an inline code tap and hold', () async {
      refused.add(7);
      final selection = facade()
        ..putBody(7, Markdown.fromString('Run `flutter run` now'));
      const hit = ChatInlineHit.code(messageId: 7, code: 'flutter run');

      expect(selection.handleInlineHit(hit), isTrue);
      await pumpEventQueue();

      expect(clipboard, isEmpty);
      expect(interactions, [
        const ChatSelectionInteraction.copyRefused(
          messageId: 7,
          origin: ChatCopyOrigin.codeTap,
          gesture: ChatInlineGesture.tap,
        ),
      ]);
      expectRefusedEvent(7, 'inlineCode');

      expect(selection.handleInlineHitLongPress(hit), isTrue);
      await pumpEventQueue();
      expect(clipboard, isEmpty);
      expect(
        interactions.last,
        const ChatSelectionInteraction.copyRefused(
          messageId: 7,
          origin: ChatCopyOrigin.codeTap,
          gesture: ChatInlineGesture.longPress,
        ),
      );
    });

    test('refuses code the host would copy itself', () async {
      refused.add(7);
      final selection = facade(copyCodeOnClick: false);

      selection.handleInlineHit(
        const ChatInlineHit.code(messageId: 7, code: 'flutter run'),
      );
      await pumpEventQueue();

      expect(interactions.whereType<ChatCodeActivated>(), isEmpty);
      expect(interactions.single, isA<ChatCopyRefused>());
    });

    test('has no fenced code copy chrome to hit', () {
      refused.add(1);
      final selection = facade(policy: const ChatSelectionPolicy.desktop())
        ..putBody(1, Markdown.fromString('```dart\nvoid main() {}\n```'));

      for (final (isHeader, isBottomBar) in [(true, false), (false, true)]) {
        expect(
          selection.inlineHitAt(
            messageId: 1,
            blockIndex: 0,
            offset: 0,
            isHeader: isHeader,
            isBottomBar: isBottomBar,
          ),
          isNull,
        );
      }
    });

    test('names a fenced block\'s copy path as the code block', () async {
      refused.add(1);
      final selection = facade()
        ..putBody(1, Markdown.fromString('```dart\nvoid main() {}\n```'));

      selection.handleInlineHit(
        const ChatInlineHit.code(
          messageId: 1,
          code: 'void main() {}',
          language: 'dart',
        ),
      );
      await pumpEventQueue();

      expectRefusedEvent(1, 'codeBlock');
    });

    test('refuses a message-selection copy that holds it', () {
      refused.add(2);
      final selection = facade();

      expect(selection.refusesCopy([1, 2, 3]), isTrue);

      expect(interactions, [
        const ChatSelectionInteraction.copyRefused(
          messageId: 2,
          origin: ChatCopyOrigin.messageSelection,
        ),
      ]);
      expectRefusedEvent(2, 'messageSelection');
      expect(facade().refusesCopy([1, 3]), isFalse);
    });
  });

  test('a live change of the answer applies to the next copy', () async {
    final selection = facade()
      ..putBody(1, Markdown.fromString('Some text'))
      ..startSelection(1);
    var notified = 0;
    selection.addListener(() => notified++);

    refused.add(1);
    selection.reapplyCanCopy();
    expect(notified, 1);
    selection.enterTextSelection(1);
    expect(await selection.copyTextSelection(), isFalse);
    expect(interactions.single, isA<ChatCopyRefused>());

    refused.clear();
    selection.reapplyCanCopy();
    expect(await selection.copyTextSelection(), isTrue);
    expect(clipboard, ['Some text']);
    expect(interactions.last, isA<ChatCopied>());
  });

  test('assigning a hook applies it and notifies', () {
    final selection = ChatSelectionController();
    addTearDown(selection.dispose);
    var notified = 0;
    selection
      ..addListener(() => notified++)
      ..canCopy = (id) => id != 4;

    expect(notified, 1);
    expect(selection.isCopyAllowed(4), isFalse);
    expect(selection.isCopyAllowed(5), isTrue);
  });

  group('the fenced code copy chrome', () {
    final theme = MarkdownThemeData(
      textStyle: const TextStyle(fontSize: 14),
      textDirection: TextDirection.ltr,
    );
    final longCode = 'final buffer = StringBuffer();\n' * 5;

    test('is not drawn for a message that may not be copied', () {
      final mobile = ChatCodeBlockPainter(
        text: longCode,
        language: 'dart',
        theme: theme,
        policy: const ChatSelectionPolicy.mobile(),
        copyable: false,
      );
      addTearDown(mobile.dispose);
      expect(mobile.hasBottomBar, isFalse);
      mobile.layout(400);
      final bottom = Offset(10, mobile.paintedBottom - 4);
      expect(mobile.isLinkAtLocal(bottom), isFalse);

      final desktop = ChatCodeBlockPainter(
        text: longCode,
        language: 'dart',
        theme: theme,
        policy: const ChatSelectionPolicy.desktop(),
        copyable: false,
      );
      addTearDown(desktop.dispose);
      desktop.layout(400);
      // The header keeps its language label; it is no button.
      expect(desktop.hasHeader, isTrue);
      expect(
        desktop.isLinkAtLocal(Offset(100, desktop.paintedTop + 10)),
        isFalse,
      );
    });

    testWidgets('leaves a mounted body when copy is refused, live', (
      tester,
    ) async {
      final selection = facade();
      selection.putBody(1, Markdown.fromString('```dart\n$longCode```'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ChatMarkdownBody(controller: selection, messageId: 1),
              ),
            ),
          ),
        ),
      );
      final withBar = tester.getSize(find.byType(ChatMarkdownBody)).height;

      refused.add(1);
      selection.reapplyCanCopy();
      await tester.pump();

      final withoutBar = tester.getSize(find.byType(ChatMarkdownBody)).height;
      expect(
        withBar - withoutBar,
        moreOrLessEquals(ChatCodeBlockPainter.mobileBottomBarHeight),
      );
    });
  });
}
