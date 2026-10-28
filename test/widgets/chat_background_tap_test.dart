import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    seedBoundaries(
      oldestKnownId: messages.first.id,
      newestKnownId: messages.last.id,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Offset _glyphPoint(ChatSelectionController selection, int id, int end) {
  final surface = selection.surfaceFor(id)!;
  final boxes = surface.localBoxesForRange(0, 0, end);
  return (surface as RenderBox).localToGlobal(boxes.first.center);
}

void main() {
  void bgTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  const viewKey = ValueKey('view');

  Future<ChatSelectionController> pump(
    WidgetTester tester, {
    required VoidCallback onBackground,
    ChatSelectionPolicy policy = const ChatSelectionPolicy.textOnly(),
    String markdown = 'Hello selectable world',
    ChatMessageMenuRequestCallback? onIdle,
    Widget Function(int id)? child,
    void Function(ChatSelectionInteraction)? onInteraction,
  }) async {
    final dataSource = _LoadedSource([_msg(1)]);
    final controller = ChatScrollController();
    final selection = ChatSelectionController(
      policy: policy,
      onInteraction: onInteraction,
    );
    addTearDown(controller.dispose);
    addTearDown(selection.dispose);
    addTearDown(dataSource.dispose);
    selection.putBody(1, Markdown.fromString(markdown));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                key: viewKey,
                dataSource: dataSource,
                controller: controller,
                selectionController: selection,
                onIdleMessageTap: onIdle,
                onBackgroundTap: onBackground,
                messageBuilder: (context, id, message, status, runLayout) =>
                    SizedBox(
                      height: 80,
                      child:
                          child?.call(id) ??
                          ChatMarkdownBody(
                            controller: selection,
                            messageId: id,
                          ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return selection;
  }

  /// A point in the viewport on the side of the one message with no row.
  Offset emptyPoint(WidgetTester tester) {
    final view = tester.getRect(find.byKey(viewKey));
    final row = tester.getRect(find.byType(ChatMarkdownBody).hitTestable());
    final y = row.center.dy > view.center.dy ? view.top + 40 : view.bottom - 40;
    return Offset(view.center.dx, y);
  }

  bgTest('tap on the empty area below the messages is a background tap', (
    tester,
  ) async {
    var calls = 0;
    await pump(tester, onBackground: () => calls++);
    await tester.tapAt(emptyPoint(tester));
    await tester.pump();
    expect(calls, 1);
  });

  bgTest('textOnly: tap on a message plain text is a background tap', (
    tester,
  ) async {
    var calls = 0;
    final selection = await pump(tester, onBackground: () => calls++);
    await tester.tapAt(_glyphPoint(selection, 1, 5));
    await tester.pump();
    expect(calls, 1);
  });

  bgTest('mobile: message tap goes to onIdleMessageTap only', (tester) async {
    var calls = 0;
    var idle = 0;
    final selection = await pump(
      tester,
      policy: const ChatSelectionPolicy.mobile(),
      onBackground: () => calls++,
      onIdle: (_) => idle++,
    );
    await tester.tapAt(_glyphPoint(selection, 1, 5));
    await tester.pump();
    expect(idle, 1);
    expect(calls, 0);
  });

  bgTest('mobile without onIdleMessageTap: message tap is background', (
    tester,
  ) async {
    var calls = 0;
    final selection = await pump(
      tester,
      policy: const ChatSelectionPolicy.mobile(),
      onBackground: () => calls++,
    );
    await tester.tapAt(_glyphPoint(selection, 1, 5));
    await tester.pump();
    expect(calls, 1);
  });

  bgTest('a row child with its own tap handler wins and is not background', (
    tester,
  ) async {
    var calls = 0;
    var button = 0;
    await pump(
      tester,
      onBackground: () => calls++,
      child: (id) => Center(
        child: TextButton(
          onPressed: () => button++,
          child: const Text('press me'),
        ),
      ),
    );
    await tester.tap(find.text('press me').first);
    await tester.pump();
    expect(button, 1);
    expect(calls, 0);
  });

  bgTest('a tap that clears a text selection is not a background tap', (
    tester,
  ) async {
    var calls = 0;
    final selection = await pump(tester, onBackground: () => calls++);
    final at = _glyphPoint(selection, 1, 5);
    await tester.longPressAt(at);
    await tester.pumpAndSettle();
    expect(selection.isTextSelectionActive, isTrue);

    await tester.tapAt(emptyPoint(tester));
    await tester.pumpAndSettle();
    expect(selection.isTextSelectionActive, isFalse);
    expect(calls, 0);

    await tester.tapAt(emptyPoint(tester));
    await tester.pump();
    expect(calls, 1);
  });

  bgTest('a tap on a link is not a background tap', (tester) async {
    var calls = 0;
    final links = <String>[];
    final selection = await pump(
      tester,
      markdown: '[Auto Docs](https://auto.com)',
      onBackground: () => calls++,
      onInteraction: (i) {
        if (i case ChatLinkActivated(:final url)) links.add(url);
      },
    );
    await tester.tapAt(_glyphPoint(selection, 1, 9));
    await tester.pumpAndSettle();
    expect(links, ['https://auto.com']);
    expect(calls, 0);
  });

  bgTest('a drag is not a background tap', (tester) async {
    var calls = 0;
    await pump(tester, onBackground: () => calls++);
    await tester.dragFrom(emptyPoint(tester), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
