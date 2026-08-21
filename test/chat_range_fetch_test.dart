import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_range_fetch.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
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

  group('ChatRangeFetch mid-flight eviction', () {
    test('same-range poll rematerializes evicted fetching chunks', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        final completer = Completer<List<IChatMessage>>();
        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) => completer.future,
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(3, 4);
        expect(chunks.containsKey(3), isTrue);
        expect(chunks[3]!.status.isFetching, isTrue);

        // Simulate LRU dropping the map entry while the token is live.
        chunks.remove(3);
        expect(fetch.coversChunkInFlight(3), isTrue);

        fetch.requestChunks(3, 4);
        expect(chunks.containsKey(3), isTrue);
        expect(chunks[3]!.status.isFetching, isTrue);
        expect(completer.isCompleted, isFalse);

        completer.complete(const <IChatMessage>[]);
        async.elapse(Duration.zero);
        expect(chunks[3]!.status.isValid, isTrue);
      });
    });

    test('does not cancel wider in-flight fetch when dirty subset shrinks', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        var fetchCalls = 0;
        final completer = Completer<List<IChatMessage>>();
        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) {
            fetchCalls++;
            return completer.future;
          },
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(96, 97);
        expect(fetchCalls, 1);
        expect(chunks[96]!.status.isFetching, isTrue);
        expect(chunks[97]!.status.isFetching, isTrue);

        // Same layout while in flight — must not restart.
        fetch.requestChunks(96, 97);
        expect(fetchCalls, 1);

        // Dirty subset shrink shape: 96 dirty again, 97 still fetching.
        chunks[96]!.status = ChatMessageStatus.dirty;
        fetch.requestChunks(96, 97);
        expect(fetchCalls, 1, reason: 'layout-bounded overlap must wait');
        expect(chunks[97]!.status.isFetching, isTrue);

        // Layout temporarily shows only 96 — still overlaps in-flight 96..97.
        fetch.requestChunks(96, 96);
        expect(fetchCalls, 1, reason: 'subset layout must not cancel sibling');

        completer.complete(const <IChatMessage>[]);
        async.elapse(Duration.zero);
      });
    });

    test('switches when layout jumps to a disjoint chunk', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        var fetchCalls = 0;
        Completer<List<IChatMessage>>? current;
        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) {
            fetchCalls++;
            current = Completer<List<IChatMessage>>();
            return current!.future;
          },
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(96, 97);
        expect(fetchCalls, 1);

        fetch.requestChunks(110, 110);
        expect(fetchCalls, 2);
        expect(fetch.coversChunkInFlight(110), isTrue);
        expect(fetch.coversChunkInFlight(96), isFalse);

        current!.complete(const <IChatMessage>[]);
        async.elapse(Duration.zero);
      });
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

  group('ChatRangeFetch absent marking', () {
    test('does not tombstone trailing nulls past highest returned id', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        // Chunk 0: ids 0..63. Return only through 40; leave 41..50 as live tail.
        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) async => <IChatMessage>[
            for (var id = fromId; id <= 40; id++) _StubMessage(id),
          ],
          notifyDataChanged: () {},
          isDisposed: () => false,
          unconfirmedTailThroughId: () => 50,
        );

        fetch.requestChunks(0, 0);
        async.elapse(Duration.zero);

        final chunk = chunks[0]!;
        expect(chunk.status.isValid, isTrue);
        expect(chunk.messages[40], isNotNull);
        expect(chunk.isAbsentSlot(30), isFalse);
        // Interior gap below maxReturned would be absent; here contiguous.
        expect(chunk.messages[45], isNull);
        expect(
          chunk.isAbsentSlot(45),
          isFalse,
          reason: 'trailing past maxReturned must stay refetchable',
        );
        expect(chunk.isAbsentSlot(50), isFalse);
      });
    });

    test('still marks interior deletes below maxReturned as absent', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) async => <IChatMessage>[
            for (var id = 1; id <= 20; id++) _StubMessage(id),
            for (var id = 40; id <= 63; id++) _StubMessage(id),
          ],
          notifyDataChanged: () {},
          isDisposed: () => false,
          unconfirmedTailThroughId: () => 63,
        );

        fetch.requestChunks(0, 0);
        async.elapse(Duration.zero);

        final chunk = chunks[0]!;
        expect(chunk.isAbsentSlot(30), isTrue);
        expect(chunk.messages[20], isNotNull);
        expect(chunk.messages[40], isNotNull);
      });
    });

    test('without unconfirmed watermark, trailing nulls stay absent', () {
      fakeAsync((async) {
        final chunks = <int, ChatScrollChunk>{};
        final fetch = ChatRangeFetch(
          chunks: () => chunks,
          fetchRange: ({required fromId, required toId}) async => <IChatMessage>[
            for (var id = fromId; id <= 1; id++) _StubMessage(id),
          ],
          notifyDataChanged: () {},
          isDisposed: () => false,
        );

        fetch.requestChunks(0, 0);
        async.elapse(Duration.zero);

        final chunk = chunks[0]!;
        expect(chunk.isAbsentSlot(2), isTrue);
        expect(chunk.isAbsentSlot(63), isTrue);
      });
    });
  });
}
