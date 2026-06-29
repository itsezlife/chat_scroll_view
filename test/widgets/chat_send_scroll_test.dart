import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

/// Preloaded source that can simulate a successful send via [simulateSend].
class _SendableDataSource extends ChatDataSource {
  _SendableDataSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  void simulateSend(int id) {
    upsertMessage(_msg(id));
    seedBoundaries(newestKnownId: id, reachedNewest: true);
    notifyDataChanged();
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          messageBuilder: (context, id, message, status) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('Send-driven scroll (US3)', () {
    testWidgets('at tail, new message stays visible after send', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController();
      final ds = _SendableDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      controller.jumpTo(count - 1);
      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      expect(controller.isAtTail.value, isTrue);

      ds.simulateSend(count);
      await tester.pumpAndSettle();

      expect(find.text('msg-$count'), findsWidgets);
    });

    testWidgets('off tail, send does not move anchor to newest', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(128);
      final ds = _SendableDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      expect(controller.isAtTail.value, isFalse);
      final anchorBefore = controller.anchorMessageId;

      ds.simulateSend(count);
      await tester.pumpAndSettle();

      expect(controller.anchorMessageId, anchorBefore);
    });
  });
}
