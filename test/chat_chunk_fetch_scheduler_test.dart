import 'package:chatscrollview/src/chat_scroll/chat_chunk_fetch_scheduler.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
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
  });
}
