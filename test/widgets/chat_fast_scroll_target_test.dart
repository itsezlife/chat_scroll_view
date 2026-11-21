/// The chat as a fast scroll target: the anchor viewport's estimated place
/// in the known span, read and moved as a fraction, against the target
/// contract.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewport_scroll/testing.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

import '../chat_message.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _Source extends ChatDataSource {
  _Source(int count) {
    upsertMessages([for (var i = 0; i < count; i++) _msg(i)]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in loadedChunks) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Future<ChatScrollController> _pumpChat(WidgetTester tester) async {
  final controller = ChatScrollController()..jumpTo(0);
  final source = _Source(200);
  addTearDown(controller.dispose);
  addTearDown(source.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: ChatScrollView(
            dataSource: source,
            controller: controller,
            messageBuilder: (context, id, message, status, runLayout) =>
                SizedBox(height: 60, child: Text('msg-$id')),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  FastScrollTargetContract.run((tester) async {
    final controller = await _pumpChat(tester);
    final target = ChatFastScrollTarget(controller);
    // The progress is published once something listens.
    void keep() {}
    target.addListener(keep);
    addTearDown(() => target.removeListener(keep));
    await _settle(tester);
    return FastScrollTargetHarness(
      target: target,
      settle: () => _settle(tester),
      tolerance: 0.02,
    );
  });

  testWidgets('the visible share is the band over the known span', (
    tester,
  ) async {
    final controller = await _pumpChat(tester);
    final target = ChatFastScrollTarget(controller);
    void keep() {}
    target.addListener(keep);
    addTearDown(() => target.removeListener(keep));
    await _settle(tester);
    // 600 of 60-tall rows: 10 of 200.
    expect(target.visibleShare, closeTo(10 / 200, 0.01));
  });

  testWidgets('a fast scrollbar drags the chat', (tester) async {
    final controller = await _pumpChat(tester);
    final target = ChatFastScrollTarget(controller);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: FastScrollbar(
              target: target,
              policy: FastScrollbarPolicy.$Android,
              style: const FastScrollbarStyle(
                thumbColor: Color(0xFFEEEEEE),
                thumbIconColor: Color(0xFF000000),
                labelColor: Color(0xFFFFFFFF),
                labelTextStyle: TextStyle(fontSize: 13),
              ),
              child: ChatScrollView(
                dataSource: _Source(200),
                controller: controller,
                messageBuilder: (context, id, message, status, runLayout) =>
                    SizedBox(height: 60, child: Text('msg-$id')),
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    target.jumpTo(0.5);
    await _settle(tester);
    expect(target.progress, closeTo(0.5, 0.02));
    expect(find.byKey(const ValueKey('fast-scrollbar-thumb')), findsOneWidget);
  });

  test('equal on one controller', () {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);
    expect(ChatFastScrollTarget(controller), ChatFastScrollTarget(controller));
  });
}
