import 'package:chat_scroll_view/chat_scroll_view.dart';
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

class _Source extends ChatDataSource {
  _Source(List<IChatMessage> messages) {
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

/// Frames the test fires by hand.
class _Frames {
  final List<VoidCallback> queue = [];
  int get requested => queue.length;

  void schedule(VoidCallback onFrame) => queue.add(onFrame);

  void fire() {
    final run = List.of(queue);
    queue.clear();
    for (final cb in run) {
      cb();
    }
  }
}

void main() {
  group('ChatStreamingBodyController', () {
    late _Frames frames;
    late ChatStreamingBodyController body;
    late int notifications;

    setUp(() {
      frames = _Frames();
      body = ChatStreamingBodyController(frameScheduler: frames.schedule);
      notifications = 0;
      body.addListener(() => notifications++);
    });

    test('starts empty and live', () {
      expect(body.value.blocks, isEmpty);
      expect(body.isSettled, isFalse);
    });

    test('many appends within a frame notify exactly once', () {
      for (var i = 0; i < 50; i++) {
        body.append('w$i ');
      }
      expect(frames.requested, 1);
      expect(notifications, 0);
      frames.fire();
      expect(notifications, 1);
      expect(body.value.markdown, contains('w49'));
    });

    test('a later frame notifies again', () {
      body.append('a');
      frames.fire();
      body.append('b');
      frames.fire();
      expect(notifications, 2);
      expect(body.value.markdown, 'ab');
    });

    test('settle replaces the accumulated text and emits once', () {
      body.append('draft');
      frames.fire();
      body.append('more');
      notifications = 0;
      body.settle('# Final');
      expect(notifications, 1);
      expect(body.value.markdown, '# Final');
      expect(body.isSettled, isTrue);
      frames.fire(); // the pending frame must not emit again
      expect(notifications, 1);
      expect(body.value.markdown, '# Final');
    });

    test('append after settle is a no-op', () {
      body.settle('done');
      notifications = 0;
      body.append('late');
      frames.fire();
      expect(notifications, 0);
      expect(frames.requested, 0);
      expect(body.value.markdown, 'done');
    });

    test('settle twice keeps the first final text', () {
      body.settle('one');
      body.settle('two');
      expect(body.value.markdown, 'one');
    });

    test('dispose cancels a pending frame; append and settle are no-ops', () {
      body.append('x');
      body.dispose();
      expect(frames.fire, returnsNormally);
      body.append('y');
      body.settle('z');
    });
  });

  group('ChatStreamingBody', () {
    Future<void> pump(
      WidgetTester tester, {
      required ChatSelectionController selection,
      required ChatDataSource source,
      required ChatScrollController scroll,
      required Map<int, ChatStreamingBodyController> bodies,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: source,
                controller: scroll,
                selectionController: selection,
                messageBuilder: (context, id, message, status, runLayout) =>
                    switch (bodies[id]) {
                      final b? => ChatStreamingBody(
                        key: ValueKey('b$id'),
                        controller: selection,
                        messageId: id,
                        body: b,
                      ),
                      _ => SizedBox(height: 40, child: Text('msg-$id')),
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('registers each text and selects and copies live and settled', (
      tester,
    ) async {
      final copied = <String>[];
      final selection = ChatSelectionController(
        copyWriter: (copy) async => copied.add(copy.plainText),
      );
      final scroll = ChatScrollController();
      final source = _Source([_msg(1), _msg(2)]);
      final body = ChatStreamingBodyController();
      addTearDown(scroll.dispose);
      addTearDown(selection.dispose);
      addTearDown(source.dispose);
      addTearDown(body.dispose);

      await pump(
        tester,
        selection: selection,
        source: source,
        scroll: scroll,
        bodies: {2: body},
      );

      body.append('hello live');
      await tester.pump(); // frame: flush
      await tester.pump();
      expect(selection.bodyOf(2)?.markdown, 'hello live');
      expect(find.byType(ChatStreamingBody), findsOneWidget);

      selection.startSelection(2);
      expect(selection.enterTextSelection(2), isTrue);
      expect(selection.selectAllText(), isTrue);
      expect(await selection.copyTextSelection(), isTrue);
      expect(copied.last, 'hello live');

      selection.clear();
      selection.clearTextSelection();
      body.settle('final **text**');
      await tester.pump();
      expect(selection.bodyOf(2)?.markdown, 'final **text**');
      selection.startSelection(2);
      expect(selection.enterTextSelection(2), isTrue);
      expect(selection.selectAllText(), isTrue);
      expect(await selection.copyTextSelection(), isTrue);
      expect(copied.last, 'final text');
    });

    testWidgets('dropping the row removes its registration', (tester) async {
      final selection = ChatSelectionController();
      final scroll = ChatScrollController();
      final source = _Source([_msg(1), _msg(2)]);
      final body = ChatStreamingBodyController()..settle('x');
      addTearDown(scroll.dispose);
      addTearDown(selection.dispose);
      addTearDown(source.dispose);
      addTearDown(body.dispose);

      await pump(
        tester,
        selection: selection,
        source: source,
        scroll: scroll,
        bodies: {2: body},
      );
      expect(selection.bodyOf(2), isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(selection.bodyOf(2), isNull);
    });

    testWidgets('inserting and removing a live row never reuses its id', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      final scroll = ChatScrollController();
      final source = _Source([_msg(1), _msg(2), _msg(3)]);
      final body = ChatStreamingBodyController();
      final built = <int>[];
      addTearDown(scroll.dispose);
      addTearDown(selection.dispose);
      addTearDown(source.dispose);
      addTearDown(body.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: source,
                controller: scroll,
                selectionController: selection,
                messageBuilder: (context, id, message, status, runLayout) {
                  built.add(id);
                  return id == 4
                      ? ChatStreamingBody(
                          controller: selection,
                          messageId: 4,
                          body: body,
                        )
                      : SizedBox(
                          key: ValueKey('row$id'),
                          height: 40,
                          child: Text('msg-$id'),
                        );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double top3() => tester.getTopLeft(find.byKey(const ValueKey('row3'))).dy;

      source.insertMessage(_msg(4));
      body.append('streaming');
      await tester.pumpAndSettle();
      expect(find.byType(ChatStreamingBody), findsOneWidget);
      final during = top3();

      source.removeMessages([4]);
      await tester.pumpAndSettle();
      expect(find.byType(ChatStreamingBody), findsNothing);
      expect(
        top3(),
        closeTo(during, 0.5),
        reason: 'removing the live row moves no surviving row',
      );

      // Absent is final: the id cannot be written back, so the host's next
      // live row takes a fresh id.
      expect(() => source.updateMessage(_msg(4)), throwsAssertionError);
      expect(selection.bodyOf(4), isNull);
      built.clear();
      await tester.pump();
      expect(built, isNot(contains(4)));
    });
  });
}
