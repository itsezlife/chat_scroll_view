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

MessageRunLayout _resolve(
  ChatDataSource ds,
  int id, {
  Object? Function(IChatMessage)? groupBy,
  ChatSenderRunLayout policy = DefaultChatSenderRunLayout.instance,
}) => policy.resolve(dataSource: ds, messageId: id, groupBy: groupBy);

void main() {
  group('DefaultChatSenderRunLayout', () {
    test('single message is first and last in run', () {
      final ds = _LoadedSource([_msg(1)]);

      final layout = _resolve(ds, 1, groupBy: null);

      expect(layout.isFirstInSenderRun, isTrue);
      expect(layout.isLastInSenderRun, isTrue);
    });

    test('three same-sender: middle is not first or last', () {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);

      final mid = _resolve(ds, 2, groupBy: null);
      expect(mid.isFirstInSenderRun, isFalse);
      expect(mid.isLastInSenderRun, isFalse);

      final last = _resolve(ds, 3, groupBy: null);
      expect(last.isFirstInSenderRun, isFalse);
      expect(last.isLastInSenderRun, isTrue);
    });

    test('bucket break splits same sender into two runs', () {
      final ds = _LoadedSource([
        _msg(1, when: _day(29)),
        _msg(2, when: _day(30)),
      ]);

      final first = _resolve(ds, 1, groupBy: _dayGroup);
      final second = _resolve(ds, 2, groupBy: _dayGroup);

      expect(first.isFirstInSenderRun, isTrue);
      expect(first.isLastInSenderRun, isTrue);
      expect(second.isFirstInSenderRun, isTrue);
      expect(second.isLastInSenderRun, isTrue);
    });

    test('different sender breaks run', () {
      final ds = _LoadedSource([_msg(1, sender: 'a'), _msg(2, sender: 'b')]);

      final layout = _resolve(ds, 2, groupBy: null);
      expect(layout.isFirstInSenderRun, isTrue);
      expect(layout.isLastInSenderRun, isTrue);
    });

    test('time window breaks same-sender run after maxClusterGap', () {
      final t0 = DateTime(2026, 5, 29, 14, 0);
      final ds = _LoadedSource([
        _msg(1, when: t0),
        _msg(2, when: t0.add(const Duration(minutes: 3))),
        _msg(3, when: t0.add(const Duration(minutes: 10))),
      ]);

      final mid = _resolve(ds, 2, groupBy: null);
      expect(mid.isFirstInSenderRun, isFalse);
      expect(mid.isLastInSenderRun, isTrue);

      final last = _resolve(ds, 3, groupBy: null);
      expect(last.isFirstInSenderRun, isTrue);
      expect(last.isLastInSenderRun, isTrue);
    });

    test('exactly maxClusterGap still clusters (Telegram ≤ window)', () {
      final t0 = DateTime(2026, 5, 29, 14, 0);
      final ds = _LoadedSource([
        _msg(1, when: t0),
        _msg(2, when: t0.add(DefaultChatSenderRunLayout.defaultMaxClusterGap)),
      ]);

      final first = _resolve(ds, 1, groupBy: null);
      final second = _resolve(ds, 2, groupBy: null);
      expect(first.isLastInSenderRun, isFalse);
      expect(second.isFirstInSenderRun, isFalse);
    });

    test('null maxClusterGap disables the time window', () {
      final t0 = DateTime(2026, 5, 29, 14, 0);
      final ds = _LoadedSource([
        _msg(1, when: t0),
        _msg(2, when: t0.add(const Duration(hours: 2))),
      ]);
      const policy = DefaultChatSenderRunLayout(maxClusterGap: null);

      final first = _resolve(ds, 1, groupBy: null, policy: policy);
      final second = _resolve(ds, 2, groupBy: null, policy: policy);
      expect(first.isLastInSenderRun, isFalse);
      expect(second.isFirstInSenderRun, isFalse);
    });

    test('unloaded message returns degenerate layout', () {
      final ds = _LoadedSource([]);
      final layout = _resolve(ds, 99, groupBy: null);
      expect(layout, const MessageRunLayout.degenerate());
    });

    test('value equality follows maxClusterGap', () {
      expect(
        // ignore: use_named_constants
        const DefaultChatSenderRunLayout(),
        DefaultChatSenderRunLayout.instance,
      );
      expect(
        const DefaultChatSenderRunLayout(maxClusterGap: null),
        isNot(DefaultChatSenderRunLayout.instance),
      );
    });
  });

  group('custom ChatSenderRunLayout', () {
    test('host policy can force every message alone', () {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      const policy = _AlwaysAloneRunLayout();

      for (final id in [1, 2, 3]) {
        final layout = _resolve(ds, id, policy: policy);
        expect(layout.isFirstInSenderRun, isTrue);
        expect(layout.isLastInSenderRun, isTrue);
      }
    });
  });
}

class _AlwaysAloneRunLayout implements ChatSenderRunLayout {
  const _AlwaysAloneRunLayout();

  @override
  MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  }) =>
      const MessageRunLayout(isFirstInSenderRun: true, isLastInSenderRun: true);
}
