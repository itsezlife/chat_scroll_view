import 'dart:async';
import 'dart:math' as math;

import 'package:chatscrollview/src/chat_scroll/chat_range_fetch.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubMessage implements IChatMessage {
  _StubMessage(this.id);

  @override
  final int id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ChatRangeFetch.nextRetryDelay', () {
    test('grows exponentially with step', () {
      final rnd = math.Random(0);
      final d0 = ChatRangeFetch.nextRetryDelay(0, random: rnd);
      final d1 = ChatRangeFetch.nextRetryDelay(1, random: rnd);
      final d2 = ChatRangeFetch.nextRetryDelay(2, random: rnd);
      expect(d0.inMilliseconds, greaterThanOrEqualTo(500));
      expect(d0.inMilliseconds, lessThan(1500));
      expect(d1.inMilliseconds, greaterThanOrEqualTo(500));
      expect(d2.inMilliseconds, greaterThanOrEqualTo(500));
      expect(d2.inMilliseconds, greaterThan(d0.inMilliseconds));
    });

    test('clamps to maxDelay', () {
      final delay = ChatRangeFetch.nextRetryDelay(
        20,
        minDelay: 500,
        maxDelay: 30000,
        random: math.Random(0),
      );
      expect(delay.inMilliseconds, lessThanOrEqualTo(30000));
    });
  });

  group('ChatRangeFetch.needsFetch', () {
    test('missing chunk needs fetch', () {
      expect(ChatRangeFetch.needsFetch(null), isTrue);
    });

    test('dirty and error chunks need fetch; fetching does not', () {
      final dirty = ChatScrollChunk(index: 0)..status = ChatMessageStatus.dirty;
      final error = ChatScrollChunk(index: 1)..status = ChatMessageStatus.error;
      final fetching = ChatScrollChunk(index: 2)
        ..status = ChatMessageStatus.fetching;
      final valid = ChatScrollChunk(index: 3)..status = ChatMessageStatus.valid;

      expect(ChatRangeFetch.needsFetch(dirty), isTrue);
      expect(ChatRangeFetch.needsFetch(error), isTrue);
      expect(ChatRangeFetch.needsFetch(fetching), isFalse);
      expect(ChatRangeFetch.needsFetch(valid), isFalse);
    });
  });

  group('ChatRangeFetch.fetchingChunks', () {
    test('tracks only chunks that need loading', () {
      final chunks = <int, ChatScrollChunk>{
        1: ChatScrollChunk(index: 1)..status = ChatMessageStatus.valid,
        2: ChatScrollChunk(index: 2)..status = ChatMessageStatus.dirty,
        3: ChatScrollChunk(index: 3)..status = ChatMessageStatus.valid,
      };
      var notifyCount = 0;
      final completer = Completer<List<IChatMessage>>();

      final fetch = ChatRangeFetch(
        chunks: () => chunks,
        fetchRange: ({required fromId, required toId}) => completer.future,
        notifyDataChanged: () => notifyCount++,
        isDisposed: () => false,
      );

      fetch.requestChunks(1, 3);
      expect(fetch.fetchingChunks, {2});
      expect(chunks[2]!.status.isFetching, isTrue);
      expect(chunks[1]!.status.isValid, isTrue);
      expect(notifyCount, 1);
    });
  });

  group('ChatRangeFetch token cancellation', () {
    test('supersedes in-flight fetch when range changes', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        final calls = <(int, int)>[];
        Completer<List<IChatMessage>>? firstCompleter;
        Completer<List<IChatMessage>>? secondCompleter;

        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) {
            calls.add((fromId, toId));
            if (calls.length == 1) {
              firstCompleter = Completer<List<IChatMessage>>();
              return firstCompleter!.future;
            }
            secondCompleter = Completer<List<IChatMessage>>();
            return secondCompleter!.future;
          },
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(0, 0);
        expect(calls, [(0, ChatScrollChunk.kSize - 1)]);
        expect(fetch.fetchingChunks, {0});

        fetch.requestChunks(1, 1);
        expect(calls.length, 2);
        expect(fetch.fetchingChunks, {1});
        expect(chunks[1]!.status.isFetching, isTrue);

        firstCompleter!.complete([_StubMessage(0)]);
        async.elapse(Duration.zero);
        // Stale completion must not touch chunk 1.
        expect(chunks[1]!.status.isFetching, isTrue);
      });
    });
  });

  group('ChatRangeFetch retry backoff', () {
    test('schedules retry after fetch error', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        var fetchCalls = 0;

        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) {
            fetchCalls++;
            if (fetchCalls == 1) {
              return Future<List<IChatMessage>>.error('network');
            }
            return Future<List<IChatMessage>>.value(const <IChatMessage>[]);
          },
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(0, 0);
        async.elapse(Duration.zero);
        expect(fetchCalls, 1);
        expect(chunks[0]!.status.isError, isTrue);

        async.elapse(const Duration(seconds: 31));
        expect(fetchCalls, 2);
        expect(chunks[0]!.status.isValid, isTrue);
      });
    });

    test('same range during pending retry is not restarted', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        var fetchCalls = 0;

        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) {
            fetchCalls++;
            return Future<List<IChatMessage>>.error('network');
          },
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(0, 0);
        async.elapse(Duration.zero);
        expect(fetchCalls, 1);

        fetch.requestChunks(0, 0);
        async.elapse(Duration.zero);
        expect(fetchCalls, 1);
      });
    });
  });
}
