import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chat_message.dart';

IChatMessage _msg(int id, {String sender = 'alice', DateTime? when}) =>
    UserChatMessage(
      id: id,
      sender: sender,
      createdAt: when ?? DateTime(2026, 5, 29, 14, id % 60),
      updatedAt: when ?? DateTime(2026, 5, 29, 14, id % 60),
      content: 'm$id',
    );

DateTime _day(int day) => DateTime(2026, 5, day);

Object _dayGroup(IChatMessage m) => DateTime(
  m.createdAt.toLocal().year,
  m.createdAt.toLocal().month,
  m.createdAt.toLocal().day,
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(Iterable<IChatMessage> messages) {
    upsertMessages(messages);
    if (messages.isEmpty) return;
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(
      oldestKnownId: ids.first,
      newestKnownId: ids.last,
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

void main() {
  group('ChatSenderRunLayout.resolve', () {
    test('single message is first and last in run', () {
      final ds = _LoadedSource([_msg(1)]);

      final layout = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: null,
        messageId: 1,
      );

      expect(layout.isFirstInSenderRun, isTrue);
      expect(layout.isLastInSenderRun, isTrue);
    });

    test('three same-sender: middle is not first or last', () {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);

      final mid = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: null,
        messageId: 2,
      );
      expect(mid.isFirstInSenderRun, isFalse);
      expect(mid.isLastInSenderRun, isFalse);

      final last = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: null,
        messageId: 3,
      );
      expect(last.isFirstInSenderRun, isFalse);
      expect(last.isLastInSenderRun, isTrue);
    });

    test('bucket break splits same sender into two runs', () {
      final ds = _LoadedSource([
        _msg(1, when: _day(29)),
        _msg(2, when: _day(30)),
      ]);

      final first = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: _dayGroup,
        messageId: 1,
      );
      final second = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: _dayGroup,
        messageId: 2,
      );

      expect(first.isFirstInSenderRun, isTrue);
      expect(first.isLastInSenderRun, isTrue);
      expect(second.isFirstInSenderRun, isTrue);
      expect(second.isLastInSenderRun, isTrue);
    });

    test('different sender breaks run', () {
      final ds = _LoadedSource([_msg(1, sender: 'a'), _msg(2, sender: 'b')]);

      final layout = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: null,
        messageId: 2,
      );
      expect(layout.isFirstInSenderRun, isTrue);
      expect(layout.isLastInSenderRun, isTrue);
    });

    test('unloaded message returns degenerate layout', () {
      final ds = _LoadedSource([]);
      final layout = ChatSenderRunLayout.resolve(
        dataSource: ds,
        groupBy: null,
        messageId: 99,
      );
      expect(layout, const MessageRunLayout.degenerate());
    });
  });
}
