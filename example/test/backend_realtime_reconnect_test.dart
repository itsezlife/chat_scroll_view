import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/data/backend_chat_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeSubscribeStatus;

Map<String, dynamic> _chat({required int? lastMessageId}) => {
  'chat': {
    'id': 1,
    'kind': 1,
    'parent_id': null,
    'created_at': 1583108356,
    'updated_at': 1583108356,
    'title': 'Demo',
    'avatar_url': null,
    'last_message': switch (lastMessageId) {
      final id? => {
        'id': id,
        'sender_id': 2,
        'created_at': 1583108356,
        'kind': 0,
        'flags': 0,
        'content_preview': 'hello',
      },
      null => null,
    },
    'unread_count': 0,
    'member_count': 1,
  },
};

void main() {
  group('BackendChatDataSource realtime reconnect', () {
    const newestBeforeDrop = 10004;

    /// A source whose `load_chat` reports [serverNewest] and whose
    /// `get_read_state` reports [serverLastRead]. The returned lists
    /// collect the invoked function names and every reported gap.
    ({
      BackendChatDataSource source,
      List<String> calls,
      List<RealtimeReconnectGap> gaps,
    })
    open({int? serverNewest = 10010, int? serverLastRead = 10002}) {
      final calls = <String>[];
      final source = BackendChatDataSource.forTest(
        invoke: (name, body) async {
          calls.add(name);
          return switch (name) {
            'load_chat' => _chat(lastMessageId: serverNewest),
            'get_read_state' => {
              'chat_id': 1,
              'user_id': 1,
              'last_read_message_id': serverLastRead,
            },
            _ => fail('unexpected $name'),
          };
        },
      )..seedBoundaries(newestKnownId: newestBeforeDrop, reachedNewest: true);
      final gaps = <RealtimeReconnectGap>[];
      source.addReconnectGapListener(gaps.add);
      addTearDown(source.dispose);
      return (source: source, calls: calls, gaps: gaps);
    }

    Future<void> statuses(
      BackendChatDataSource source,
      List<RealtimeSubscribeStatus> statuses,
    ) async {
      for (final status in statuses) {
        await source.applyRealtimeStatusForTest(status);
      }
    }

    test('a resubscribe after a drop re-reads the newest id and reports the '
        'gap from the newest id known before the drop', () async {
      final (:source, :calls, :gaps) = open();

      await statuses(source, const [
        RealtimeSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.channelError,
        RealtimeSubscribeStatus.subscribed,
      ]);

      expect(calls, unorderedEquals(<String>['load_chat', 'get_read_state']));
      expect(source.newestKnownId, 10010);
      expect(source.reachedNewest, isTrue);
      expect(gaps, <RealtimeReconnectGap>[
        (newestBeforeDrop: newestBeforeDrop, lastReadMessageId: 10002),
      ]);
    });

    test('a drop during a re-read reports each missed span once', () async {
      final gate = Completer<void>();
      var serverNewest = 10010;
      final gaps = <RealtimeReconnectGap>[];
      final source =
          BackendChatDataSource.forTest(
              invoke: (name, _) async {
                if (name == 'load_chat') {
                  final newest = serverNewest;
                  await gate.future;
                  return _chat(lastMessageId: newest);
                }
                return {
                  'chat_id': 1,
                  'user_id': 1,
                  'last_read_message_id': 10002,
                };
              },
            )
            ..seedBoundaries(
              newestKnownId: newestBeforeDrop,
              reachedNewest: true,
            )
            ..addReconnectGapListener(gaps.add);
      addTearDown(source.dispose);

      await statuses(source, const [
        RealtimeSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.channelError,
      ]);
      final first = source.applyRealtimeStatusForTest(
        RealtimeSubscribeStatus.subscribed,
      );
      await source.applyRealtimeStatusForTest(
        RealtimeSubscribeStatus.channelError,
      );
      serverNewest = 10013;
      final second = source.applyRealtimeStatusForTest(
        RealtimeSubscribeStatus.subscribed,
      );
      gate.complete();
      await (first, second).wait;

      expect(gaps, <RealtimeReconnectGap>[
        (newestBeforeDrop: newestBeforeDrop, lastReadMessageId: 10002),
        (newestBeforeDrop: 10010, lastReadMessageId: 10002),
      ]);
      expect(source.newestKnownId, 10013);
    });

    test('a closed or timed-out channel counts as a drop', () async {
      final (:source, :calls, :gaps) = open();

      await statuses(source, const [
        RealtimeSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.timedOut,
        RealtimeSubscribeStatus.closed,
        RealtimeSubscribeStatus.subscribed,
      ]);

      expect(gaps, hasLength(1));
      expect(gaps.single.newestBeforeDrop, newestBeforeDrop);
    });

    test('the first subscribe is not a reconnect, even after a failed '
        'attempt', () async {
      final (:source, :calls, :gaps) = open();

      await statuses(source, const [
        RealtimeSubscribeStatus.timedOut,
        RealtimeSubscribeStatus.subscribed,
      ]);

      expect(calls, isEmpty);
      expect(gaps, isEmpty);
    });

    test('a reconnect with no new messages reports nothing and keeps the '
        'newest id', () async {
      final (:source, :calls, :gaps) = open(serverNewest: newestBeforeDrop);

      await statuses(source, const [
        RealtimeSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.channelError,
        RealtimeSubscribeStatus.subscribed,
      ]);

      expect(calls, contains('load_chat'));
      expect(gaps, isEmpty);
      expect(source.newestKnownId, newestBeforeDrop);
    });

    test(
      'a drop from an empty chat re-reads, reseeds the chat like a fresh '
      'connect, and reports a gap with no newest id before the drop',
      () async {
        final (:source, :calls, :gaps) = open();
        source.seedBoundaries(
          oldestKnownId: null,
          newestKnownId: null,
          reachedOldest: true,
          reachedNewest: true,
        );

        await statuses(source, const [
          RealtimeSubscribeStatus.subscribed,
          RealtimeSubscribeStatus.channelError,
          RealtimeSubscribeStatus.subscribed,
        ]);

        expect(source.newestKnownId, 10010);
        expect(source.reachedOldest, isFalse);
        expect(source.reachedNewest, isTrue);
        expect(gaps, <RealtimeReconnectGap>[
          (newestBeforeDrop: null, lastReadMessageId: 10002),
        ]);
      },
    );

    test(
      'a drop from an empty chat that is still empty reports nothing',
      () async {
        final (:source, :calls, :gaps) = open(serverNewest: null);
        source.seedBoundaries(
          oldestKnownId: null,
          newestKnownId: null,
          reachedOldest: true,
          reachedNewest: true,
        );

        await statuses(source, const [
          RealtimeSubscribeStatus.subscribed,
          RealtimeSubscribeStatus.channelError,
          RealtimeSubscribeStatus.subscribed,
        ]);

        expect(calls, contains('load_chat'));
        expect(gaps, isEmpty);
        expect(source.isEmpty, isTrue);
      },
    );

    test('a failed re-read reports nothing', () async {
      final gaps = <RealtimeReconnectGap>[];
      final source =
          BackendChatDataSource.forTest(
              invoke: (name, _) async => {
                'error': {'slug': 'service_unavailable', 'message': 'down'},
              },
            )
            ..seedBoundaries(
              newestKnownId: newestBeforeDrop,
              reachedNewest: true,
            )
            ..addReconnectGapListener(gaps.add);
      addTearDown(source.dispose);

      await statuses(source, const [
        RealtimeSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.channelError,
        RealtimeSubscribeStatus.subscribed,
      ]);

      expect(gaps, isEmpty);
      expect(source.newestKnownId, newestBeforeDrop);
    });

    test(
      'a removed listener hears nothing; adding one twice hears once',
      () async {
        final (:source, :calls, :gaps) = open();
        final second = <RealtimeReconnectGap>[];
        source
          ..addReconnectGapListener(second.add)
          ..addReconnectGapListener(second.add)
          ..removeReconnectGapListener(gaps.add);

        await statuses(source, const [
          RealtimeSubscribeStatus.subscribed,
          RealtimeSubscribeStatus.channelError,
          RealtimeSubscribeStatus.subscribed,
        ]);

        expect(gaps, isEmpty);
        expect(second, hasLength(1));
      },
    );

    test('nothing is re-read or reported after dispose', () async {
      final (:source, :calls, :gaps) = open();
      await statuses(source, const [
        RealtimeSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.channelError,
      ]);
      source.dispose();

      await source.applyRealtimeStatusForTest(
        RealtimeSubscribeStatus.subscribed,
      );

      expect(calls, isEmpty);
      expect(gaps, isEmpty);
    });
  });
}
