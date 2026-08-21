import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/chat_chunk_fetch_scheduler.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestDataSource extends ChatDataSource {
  _TestDataSource({this.chunkBudget = 16});

  final int chunkBudget;

  @override
  int get maxChunks => chunkBudget;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

class _HangingFetchDataSource extends ChatDataSource {
  _HangingFetchDataSource(this.pending, {this.chunkBudget = 16});

  final Completer<List<IChatMessage>> pending;
  final int chunkBudget;

  @override
  int get maxChunks => chunkBudget;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) => pending.future;
}

void _flushPostFrameCallbacks() {
  SchedulerBinding.instance
    ..scheduleFrame()
    ..handleBeginFrame(Duration.zero)
    ..handleDrawFrame();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('jump fetch', () {
    test('dispatches requestRange after layout on post-frame', () {
      fakeAsync((_) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler =
            ChatChunkFetchScheduler(
                dataSource: dataSource,
                requestRange: (min, max) => requested.add((min, max)),
                anchorChunkIndex: () => 0,
              )
              ..onJump()
              ..onLayoutComplete(2, 5);
        expect(requested, isEmpty);

        _flushPostFrameCallbacks();
        expect(requested, [(2, 5)]);
        scheduler.dispose();
      });
    });

    test('does not dispatch when detached', () {
      fakeAsync((_) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler =
            ChatChunkFetchScheduler(
                dataSource: dataSource,
                requestRange: (min, max) => requested.add((min, max)),
                anchorChunkIndex: () => 0,
              )
              ..onDetach()
              ..onJump()
              ..onLayoutComplete(1, 3);
        _flushPostFrameCallbacks();
        expect(requested, isEmpty);
        scheduler.dispose();
      });
    });
  });

  group('scheduleFetchPoll', () {
    test('does not arm when all chunks in range are valid', () {
      fakeAsync((async) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 0,
        );

        for (var ci = 1; ci <= 3; ci++) {
          dataSource.chunks[ci] = ChatScrollChunk(index: ci)
            ..status = ChatMessageStatus.valid;
        }

        scheduler.onLayoutComplete(1, 3);
        async.elapse(const Duration(milliseconds: 200));
        expect(requested, isEmpty);
        scheduler.dispose();
      });
    });

    test('arms poll when a chunk is missing', () {
      fakeAsync((async) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) {
            requested.add((min, max));
            // Mirror [ChatDataSource.requestChunks] marking chunks in-flight so
            // the poll loop goes idle instead of re-arming forever.
            for (var ci = min; ci <= max; ci++) {
              dataSource.chunks[ci] ??= ChatScrollChunk(index: ci);
              dataSource.chunks[ci]!.status = ChatMessageStatus.fetching;
            }
          },
          anchorChunkIndex: () => 0,
        );

        dataSource.chunks[2] = ChatScrollChunk(index: 2)
          ..status = ChatMessageStatus.valid;

        scheduler.onLayoutComplete(1, 3);
        async.elapse(Duration.zero);
        expect(requested, [(1, 3)]);
        scheduler.dispose();
      });
    });

    test('does not arm when chunk in range is errored', () {
      fakeAsync((async) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 0,
        );

        dataSource.chunks[2] = ChatScrollChunk(index: 2)
          ..status = ChatMessageStatus.error;

        scheduler.onLayoutComplete(2, 2);
        async.elapse(const Duration(milliseconds: 200));
        expect(requested, isEmpty);
        scheduler.dispose();
      });
    });
  });

  group('evictChunks', () {
    test('evicts outside-layout chunks when at budget', () {
      final dataSource = _TestDataSource(chunkBudget: 2);
      final scheduler = ChatChunkFetchScheduler(
        dataSource: dataSource,
        requestRange: (_, _) {},
        anchorChunkIndex: () => 1,
      );

      for (final ci in [0, 5]) {
        dataSource.chunks[ci] = ChatScrollChunk(index: ci)
          ..status = ChatMessageStatus.valid
          ..lastAccessTick = ci;
      }

      scheduler.onLayoutComplete(1, 2);
      expect(dataSource.chunks.containsKey(0), isFalse);
      expect(dataSource.chunks.containsKey(5), isFalse);
      scheduler.dispose();
    });

    test('never evicts in-flight fetching chunks', () {
      fakeAsync((async) {
        final pending = Completer<List<IChatMessage>>();
        final dataSource = _HangingFetchDataSource(pending, chunkBudget: 1);
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: dataSource.requestChunks,
          anchorChunkIndex: () => 0,
        );

        dataSource.chunks[0] = ChatScrollChunk(index: 0)
          ..status = ChatMessageStatus.valid
          ..lastAccessTick = 0;

        dataSource.requestChunks(5, 5);
        expect(dataSource.coversChunkInFlight(5), isTrue);
        expect(dataSource.chunks[5]!.status.isFetching, isTrue);

        // Layout only at anchor — chunk 5 is outside and would normally be
        // the eviction victim under budget=1.
        scheduler.onLayoutComplete(0, 0);
        expect(
          dataSource.chunks.containsKey(5),
          isTrue,
          reason: 'in-flight chunk must survive LRU',
        );
        expect(dataSource.coversChunkInFlight(5), isTrue);

        pending.complete(const <IChatMessage>[]);
        async.elapse(Duration.zero);
        scheduler.dispose();
      });
    });

    test('never evicts anchor chunk', () {
      final dataSource = _TestDataSource(chunkBudget: 1);
      final scheduler = ChatChunkFetchScheduler(
        dataSource: dataSource,
        requestRange: (_, _) {},
        anchorChunkIndex: () => 2,
      );

      dataSource.chunks[2] = ChatScrollChunk(index: 2)
        ..status = ChatMessageStatus.valid
        ..lastAccessTick = 0;
      dataSource.chunks[3] = ChatScrollChunk(index: 3)
        ..status = ChatMessageStatus.valid
        ..lastAccessTick = 1;

      scheduler.onLayoutComplete(2, 3);
      expect(dataSource.chunks.containsKey(2), isTrue);
      expect(dataSource.chunks.containsKey(3), isFalse);
      scheduler.dispose();
    });

    test('protects destination-window chunks during load-gate', () {
      final dataSource = _TestDataSource(chunkBudget: 2);
      final scheduler = ChatChunkFetchScheduler(
        dataSource: dataSource,
        requestRange: (_, _) {},
        anchorChunkIndex: () => 0,
      );

      // Layout around chunk 0; destination window around chunk 10.
      for (final ci in [0, 1, 9, 10, 11]) {
        dataSource.chunks[ci] = ChatScrollChunk(index: ci)
          ..status = ChatMessageStatus.valid
          ..lastAccessTick = ci;
      }
      scheduler.setNavigationDestinationId(ChatScrollChunk.firstIdOf(10));
      scheduler.onLayoutComplete(0, 1);

      expect(dataSource.chunks.containsKey(9), isTrue);
      expect(dataSource.chunks.containsKey(10), isTrue);
      expect(dataSource.chunks.containsKey(11), isTrue);
      scheduler.dispose();
    });
  });

  group('destination window fetch', () {
    test('requests around-target window only — not layout…target gap', () {
      fakeAsync((_) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 0,
        );

        // Origin layout is far from destination chunk 10.
        scheduler
          ..onLayoutComplete(0, 1)
          ..setNavigationDestinationId(ChatScrollChunk.firstIdOf(10));
        _flushPostFrameCallbacks();

        expect(requested, isNotEmpty);
        for (final range in requested) {
          expect(range.$1, 10 - ChatChunkFetchScheduler.destinationWindowRadiusChunks);
          expect(range.$2, 10 + ChatChunkFetchScheduler.destinationWindowRadiusChunks);
        }
        expect(
          requested.any((r) => r.$1 <= 0 && r.$2 >= 10),
          isFalse,
          reason: 'must not contiguous-fill origin…target',
        );
        scheduler.dispose();
      });
    });

    test('jump fetch uses layout when dest pin set but layout is local', () {
      fakeAsync((_) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 0,
        );

        // Dest pin at chunk 5; scrollbar-like layout elsewhere (no stitch gap).
        // Without clearing the pin this is load-gate-at-origin shape — warm
        // dest only. Scrollbar path clears the pin before jump-fetch.
        scheduler
          ..setNavigationDestinationId(ChatScrollChunk.firstIdOf(5))
          ..clearNavigationDestination()
          ..onJump()
          ..onLayoutComplete(10, 11);
        _flushPostFrameCallbacks();

        expect(requested, isNotEmpty);
        expect(
          requested.any((r) => r.$1 == 10 && r.$2 == 11),
          isTrue,
          reason: 'jump-fetch must load the on-screen band after pin clear',
        );
        scheduler.dispose();
      });
    });

    test('jump fetch keeps dest when pin set and layout is still at origin', () {
      fakeAsync((_) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 0,
        );

        scheduler
          ..onLayoutComplete(0, 1)
          ..setNavigationDestinationId(ChatScrollChunk.firstIdOf(10))
          ..onJump()
          ..onLayoutComplete(0, 1);
        _flushPostFrameCallbacks();

        expect(requested, isNotEmpty);
        expect(
          requested.every(
            (r) =>
                r.$1 ==
                    10 -
                        ChatChunkFetchScheduler
                            .destinationWindowRadiusChunks &&
                r.$2 ==
                    10 +
                        ChatChunkFetchScheduler
                            .destinationWindowRadiusChunks,
          ),
          isTrue,
          reason: 'load-gate at origin must not cancel dest with layout fetch',
        );
        scheduler.dispose();
      });
    });

    test('jump fetch diverts to dest only when layout spans stitch gap', () {
      fakeAsync((_) {
        final dataSource = _TestDataSource();
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 0,
        );

        scheduler
          ..setNavigationDestinationId(ChatScrollChunk.firstIdOf(5))
          ..onJump()
          // Dual-strip: outgoing near 0 and incoming through dest 5.
          ..onLayoutComplete(0, 20);
        _flushPostFrameCallbacks();

        expect(requested, isNotEmpty);
        expect(
          requested.every(
            (r) =>
                r.$1 == 5 - ChatChunkFetchScheduler.destinationWindowRadiusChunks &&
                r.$2 == 5 + ChatChunkFetchScheduler.destinationWindowRadiusChunks,
          ),
          isTrue,
          reason: 'stitch dual-strip must not gap-fill layout min…max',
        );
        scheduler.dispose();
      });
    });

    test('clamps destination window to known ids (no perpetual chunk -1 poll)', () {
      fakeAsync((async) {
        final dataSource = _TestDataSource()
          ..seedBoundaries(
            oldestKnownId: 0,
            newestKnownId: 200,
            reachedOldest: true,
            reachedNewest: true,
          );
        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) => requested.add((min, max)),
          anchorChunkIndex: () => 3,
        );

        // Target id 50 → chunk 0; unclamped window would be -1..1.
        scheduler.setNavigationDestinationId(50);
        _flushPostFrameCallbacks();
        expect(requested, isNotEmpty);
        expect(requested.last.$1, 0);
        expect(requested.last.$2, 1);

        // Satisfy the window before draining the poll armed while pending.
        // Mark every slot absent so the known span is confirmed empty (not
        // unloaded holes) — otherwise hasKnownSpanHoles keeps the poll armed.
        for (final ci in [0, 1]) {
          final chunk = ChatScrollChunk(index: ci)
            ..status = ChatMessageStatus.valid;
          for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
            chunk.markAbsentSlot(slot);
          }
          dataSource.chunks[ci] = chunk;
        }
        async.elapse(const Duration(milliseconds: 200));
        requested.clear();
        scheduler.onLayoutComplete(3, 3);
        async.elapse(const Duration(milliseconds: 200));
        expect(requested, isEmpty, reason: 'valid dest window must idle the poll');
        scheduler.dispose();
      });
    });

    test('poll stays armed when valid dest chunk has trailing absent holes', () {
      fakeAsync((async) {
        final dataSource = _TestDataSource();
        // Inserts set the unconfirmed-tail watermark, then we simulate a stale
        // fetch that tombstoned those ids while leaving older payloads.
        for (var id = 0; id <= 50; id++) {
          dataSource.insertMessage(_SchedStubMessage(id));
        }
        final chunk = dataSource.chunks[0]!;
        for (var id = 41; id <= 50; id++) {
          chunk.messages[id] = null;
          chunk.markAbsentSlot(id);
        }
        chunk.status = ChatMessageStatus.valid;

        expect(dataSource.hasKnownSpanHoles(0), isTrue);

        final requested = <(int, int)>[];
        final scheduler = ChatChunkFetchScheduler(
          dataSource: dataSource,
          requestRange: (min, max) {
            requested.add((min, max));
            dataSource.requestChunks(min, max);
          },
          anchorChunkIndex: () => 0,
        );

        scheduler.setNavigationDestinationId(50);
        _flushPostFrameCallbacks();
        expect(requested, isNotEmpty);

        // Heal clears trailing absents so the known newest can refetch.
        expect(dataSource.chunks[0]!.isAbsentSlot(50), isFalse);
        expect(dataSource.hasKnownSpanHoles(0), isTrue);

        // Hole-only pending uses poll interval (no Duration.zero busy-spin).
        async.elapse(const Duration(milliseconds: 200));
        expect(requested.length, greaterThan(1));
        scheduler.dispose();
      });
    });
  });
}

class _SchedStubMessage implements IChatMessage {
  _SchedStubMessage(this.id);

  @override
  final int id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
