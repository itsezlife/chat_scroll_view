import 'dart:async';

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_widgets/chat_data_source_ext.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'u',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'm$id',
);

class _TestDataSource extends ChatDataSource {
  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

void main() {
  group('ChatScrollChunk.chunkOf', () {
    final cases = <(int id, int expected)>[
      (0, 0),
      (63, 0),
      (64, 1),
      (-1, -1),
      (1000, 15),
      (4000, 62),
    ];

    for (final (id, expected) in cases) {
      test('chunkOf($id) == $expected', () {
        expect(ChatScrollChunk.chunkOf(id), expected);
      });
    }
  });

  group('ChatScrollChunk.firstIdOf', () {
    test('firstIdOf(0) == 0', () {
      expect(ChatScrollChunk.firstIdOf(0), 0);
    });

    test('firstIdOf(1) == 64', () {
      expect(ChatScrollChunk.firstIdOf(1), 64);
    });
  });

  group('ChatScrollChunk.isFullChunkRange', () {
    test('single full chunk 0..63 is valid', () {
      expect(ChatScrollChunk.isFullChunkRange(0, 63), isTrue);
    });

    test('single full chunk 64..127 is valid', () {
      expect(ChatScrollChunk.isFullChunkRange(64, 127), isTrue);
    });

    test('spanning two whole chunks 0..127 is valid', () {
      expect(ChatScrollChunk.isFullChunkRange(0, 127), isTrue);
    });

    test('partial start inside chunk 1 is invalid', () {
      expect(ChatScrollChunk.isFullChunkRange(65, 127), isFalse);
    });

    test('partial end inside chunk 1 is invalid', () {
      expect(ChatScrollChunk.isFullChunkRange(64, 126), isFalse);
    });

    test('partial sub-range 70..90 inside chunk 1 is invalid', () {
      expect(ChatScrollChunk.isFullChunkRange(70, 90), isFalse);
    });

    test('inverted range is invalid', () {
      expect(ChatScrollChunk.isFullChunkRange(63, 0), isFalse);
    });
  });

  group('ChatScrollChunk.lastId', () {
    test('index 0 spans ids 0..63', () {
      final chunk = ChatScrollChunk(index: 0);
      expect(chunk.lastId, 63);
      expect(chunk.firstId, 0);
    });

    test('chunks 62 and 63 after bulk delete gap keep correct bounds', () {
      final c62 = ChatScrollChunk(index: 62);
      final c63 = ChatScrollChunk(index: 63);
      expect(c62.firstId, 62 * ChatScrollChunk.kSize);
      expect(c62.lastId, 63 * ChatScrollChunk.kSize - 1);
      expect(c63.firstId, 63 * ChatScrollChunk.kSize);
      expect(c63.lastId, 64 * ChatScrollChunk.kSize - 1);
      // IDs 4000–4099 absent — null slots are legal in both chunks.
      expect(c62.messages.every((m) => m == null), isTrue);
      expect(c63.messages.every((m) => m == null), isTrue);
    });
  });

  group('ChatDataSource.getMessage sparse ids', () {
    late _TestDataSource source;

    setUp(() {
      source = _TestDataSource()
        ..upsertMessage(_msg(100))
        ..upsertMessage(_msg(199));
    });

    test(
      'getMessage(100) returns message when 101–198 are null in chunk 1',
      () {
        final m = source.getMessage(100);
        expect(m, isNotNull);
        expect(m!.id, 100);
        expect(source.getMessage(101), isNull);
        expect(source.getMessage(150), isNull);
        expect(source.getMessage(198), isNull);
        expect(source.getMessage(199)!.id, 199);
      },
    );

    test('slot assertion fires when chunk is stored at wrong index', () {
      // Chunk for index 0 (firstId 0) stored under key 1 — simulates corruption.
      source.chunks[1] = ChatScrollChunk(index: 0);

      expect(() => source.getMessage(64), throwsA(isA<AssertionError>()));
    });
  });

  group('ChatScrollChunk absent mask', () {
    late ChatScrollChunk chunk;

    setUp(() {
      chunk = ChatScrollChunk(index: 0);
    });

    test('markAbsentSlot(0) sets bit 0 — isAbsentSlot(0) is true', () {
      chunk.markAbsentSlot(0);
      expect(chunk.isAbsentSlot(0), isTrue);
      expect(chunk.isAbsentSlot(1), isFalse);
    });

    test('markAbsentSlot(63) sets bit 63 — isAbsentSlot(63) is true', () {
      chunk.markAbsentSlot(63);
      expect(chunk.isAbsentSlot(63), isTrue);
      // bit 63 set in two's complement does not corrupt lower bits
      expect(chunk.isAbsentSlot(0), isFalse);
    });

    test('clearAbsentMask resets all bits', () {
      chunk
        ..markAbsentSlot(0)
        ..markAbsentSlot(32)
        ..markAbsentSlot(63)
        ..clearAbsentMask();
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        expect(chunk.isAbsentSlot(i), isFalse, reason: 'slot $i should be clear');
      }
    });

    test('isFullyAbsent is true when all 64 slots are marked absent', () {
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        chunk.markAbsentSlot(i);
      }
      expect(chunk.isFullyAbsent, isTrue);
    });

    test('isFullyAbsent is false when only some slots are marked', () {
      chunk.markAbsentSlot(0);
      expect(chunk.isFullyAbsent, isFalse);
      expect(chunk.absentSlotCount, 1);
    });

    test('isFullyAbsent becomes true only after all 64 slots are marked', () {
      for (var slot = 0; slot < ChatScrollChunk.kSize - 1; slot++) {
        chunk.markAbsentSlot(slot);
      }
      expect(chunk.isFullyAbsent, isFalse);
      expect(chunk.absentSlotCount, ChatScrollChunk.kSize - 1);

      chunk.markAbsentSlot(ChatScrollChunk.kSize - 1);
      expect(chunk.isFullyAbsent, isTrue);
      expect(chunk.absentSlotCount, ChatScrollChunk.kSize);
    });

    test('clearAbsentSlot on a fully absent chunk clears isFullyAbsent', () {
      for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
        chunk.markAbsentSlot(slot);
      }
      expect(chunk.isFullyAbsent, isTrue);

      chunk.clearAbsentSlot(0);
      expect(chunk.isFullyAbsent, isFalse);
      expect(chunk.absentSlotCount, ChatScrollChunk.kSize - 1);
      expect(chunk.isAbsentSlot(0), isFalse);
    });

    test('clearAbsentMask on a fully absent chunk resets isFullyAbsent', () {
      for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
        chunk.markAbsentSlot(slot);
      }
      chunk.clearAbsentMask();
      expect(chunk.isFullyAbsent, isFalse);
      expect(chunk.absentSlotCount, 0);
    });

    test('contiguous partial absence leaves isFullyAbsent false', () {
      for (var slot = 10; slot <= 20; slot++) {
        chunk.markAbsentSlot(slot);
      }
      expect(chunk.isFullyAbsent, isFalse);
      expect(chunk.absentSlotCount, 11);
      for (var slot = 0; slot < 10; slot++) {
        expect(chunk.isAbsentSlot(slot), isFalse);
      }
      for (var slot = 21; slot < ChatScrollChunk.kSize; slot++) {
        expect(chunk.isAbsentSlot(slot), isFalse);
      }
    });

    test(
      'markAbsentSlot on a null unmarked slot succeeds and sets the bit',
      () {
        expect(chunk.messages[7], isNull);
        expect(chunk.isAbsentSlot(7), isFalse);

        chunk.markAbsentSlot(7);

        expect(chunk.isAbsentSlot(7), isTrue);
        expect(chunk.messages[7], isNull);
        expect(chunk.isFullyAbsent, isFalse);
      },
    );

    test('markAbsentSlot is idempotent when the slot is already absent', () {
      chunk.markAbsentSlot(4);
      chunk.markAbsentSlot(4);
      expect(chunk.isAbsentSlot(4), isTrue);
      expect(chunk.absentSlotCount, 1);
    });

    test(
      'markAbsentSlot throws AssertionError in debug mode when slot is '
      'non-null',
      () {
        final msg = _msg(5);
        chunk.messages[5] = msg;
        // markAbsentSlot(5) must assert because messages[5] is non-null.
        expect(() => chunk.markAbsentSlot(5), throwsA(isA<AssertionError>()));
      },
    );

    test('clearAbsentSlot clears the bit for the given slot', () {
      chunk.markAbsentSlot(3);
      expect(chunk.isAbsentSlot(3), isTrue);
      chunk.clearAbsentSlot(3);
      expect(chunk.isAbsentSlot(3), isFalse);
    });

    test('clearAbsentSlot is idempotent when bit is already zero', () {
      expect(chunk.isAbsentSlot(7), isFalse);
      // Should not throw or change state.
      chunk.clearAbsentSlot(7);
      expect(chunk.isAbsentSlot(7), isFalse);
    });

    test('clearAbsentSlot only clears the targeted bit, leaving others set',
        () {
      chunk
        ..markAbsentSlot(0)
        ..markAbsentSlot(10)
        ..markAbsentSlot(63);
      chunk.clearAbsentSlot(10);
      expect(chunk.isAbsentSlot(0), isTrue);
      expect(chunk.isAbsentSlot(10), isFalse);
      expect(chunk.isAbsentSlot(63), isTrue);
    });
  });

  group('statusOf with absent mask', () {
    late _TestDataSource source;

    setUp(() {
      source = _TestDataSource();
    });

    test('statusOf returns dirty for an unloaded chunk', () {
      expect(source.statusOf(0), ChatMessageStatus.dirty);
    });

    test('statusOf returns valid for a present slot in a valid chunk', () {
      source.upsertMessage(_msg(10));
      expect(source.statusOf(10), ChatMessageStatus.valid);
    });

    test('statusOf returns absent for a slot marked absent in a valid chunk',
        () {
      source.upsertMessage(_msg(10));
      // Manually mark slot 5 (id = chunkFirstId + 5 = 5) absent.
      final chunkIndex = ChatScrollChunk.chunkOf(0);
      final chunk = source.chunks[chunkIndex]!;
      chunk.markAbsentSlot(5); // id = 0 * 64 + 5 = 5
      expect(source.statusOf(5), ChatMessageStatus.absent);
    });

    test('statusOf returns chunk status (valid) for a null non-absent slot',
        () {
      source.upsertMessage(_msg(10));
      // id=11 is in chunk 0 but not absent and not present.
      expect(source.statusOf(11), ChatMessageStatus.valid);
    });
  });

  // ---------------------------------------------------------------------------
  // Absent-marking scope after fetchRange
  // ---------------------------------------------------------------------------

  group('ChatDataSource absent-marking after fetchRange', () {
    // Verify that ALL null slots in fetched chunks are marked absent
    // unconditionally — no [oldestKnownId, newestKnownId] guard.

    test(
      'empty fetch below current oldestKnownId marks every slot absent',
      () async {
        // Seed two real messages so oldestKnownId = 10001, newestKnownId = 10004.
        final source = _RecordingDataSource(fetchResult: []);
        source
          ..upsertMessage(_msg(10001))
          ..upsertMessage(_msg(10004));

        // oldestKnownId = 10001 (from upsert, no fetch yet sets it lower).
        // We now ask for a range that lives entirely BELOW 10001.
        // The chunk covering 9984–10047 (index 156) would cover 9984..10047.
        // Let's use a simpler range: IDs 64–127 (chunk index 1).
        // fetchRange returns empty → all 64 slots in chunk 1 must be absent.
        source.simulateFetch(fromId: 64, toId: 127, result: []);
        await Future<void>.delayed(Duration.zero); // let future complete

        final ci = ChatScrollChunk.chunkOf(64);
        final chunk = source.chunks[ci];
        expect(chunk, isNotNull, reason: 'chunk must be created by the fetch');
        final loaded = chunk!;
        for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
          expect(
            loaded.isAbsentSlot(slot),
            isTrue,
            reason: 'slot $slot (id ${64 + slot}) must be absent after '
                'empty fetch even though 64 < oldestKnownId (10001)',
          );
        }
        expect(loaded.isFullyAbsent, isTrue);
        expect(loaded.absentSlotCount, ChatScrollChunk.kSize);
      },
    );

    test(
      'partial result: returned IDs are present, unreturned are absent',
      () async {
        final source = _RecordingDataSource(fetchResult: []);
        // Fetch chunk 0 (IDs 0–63) with only ID 5 returned.
        source.simulateFetch(fromId: 0, toId: 63, result: [_msg(5)]);
        await Future<void>.delayed(Duration.zero);

        final ci = ChatScrollChunk.chunkOf(0);
        final chunk = source.chunks[ci];
        expect(chunk, isNotNull);
        // Slot 5 is present → not absent.
        expect(chunk!.isAbsentSlot(5), isFalse);
        expect(chunk.messages[5], isNotNull);
        // Every other slot is absent.
        for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
          if (slot == 5) continue;
          expect(
            chunk.isAbsentSlot(slot),
            isTrue,
            reason: 'slot $slot must be absent',
          );
        }
      },
    );

    test(
      'sparse fetchRange result marks only unreturned slots absent',
      () async {
        final source = _RecordingDataSource(fetchResult: []);
        source.simulateFetch(
          fromId: 0,
          toId: 63,
          result: [_msg(5), _msg(10)],
        );
        await Future<void>.delayed(Duration.zero);

        final chunk = source.chunks[ChatScrollChunk.chunkOf(0)]!;
        expect(chunk.messages[5], isNotNull);
        expect(chunk.messages[10], isNotNull);
        expect(chunk.isAbsentSlot(5), isFalse);
        expect(chunk.isAbsentSlot(10), isFalse);
        expect(chunk.isAbsentSlot(0), isTrue);
        expect(chunk.isAbsentSlot(63), isTrue);
        expect(chunk.isFullyAbsent, isFalse);
        expect(chunk.absentSlotCount, ChatScrollChunk.kSize - 2);
      },
    );

    test(
      'large deletion gap across five whole chunks marks every slot absent',
      () async {
        final source = _RecordingDataSource(fetchResult: []);
        // Chunks 1–5 (ids 64–383) empty; anchors at chunk 0 and 6 edges.
        source.simulateFetch(
          fromId: 64,
          toId: 383,
          result: const <IChatMessage>[],
        );
        await Future<void>.delayed(Duration.zero);

        for (var ci = 1; ci <= 5; ci++) {
          final chunk = source.chunks[ci];
          expect(chunk, isNotNull, reason: 'chunk $ci must exist');
          expect(chunk!.isFullyAbsent, isTrue);
          expect(chunk.absentSlotCount, ChatScrollChunk.kSize);
        }
        expect(source.statusOf(64).isAbsent, isTrue);
        expect(source.statusOf(200).isAbsent, isTrue);
        expect(source.statusOf(383).isAbsent, isTrue);
      },
    );

    test(
      'chunk boundary ids: first and last slot in a chunk mark absent correctly',
      () async {
        final source = _RecordingDataSource(fetchResult: []);
        source.simulateFetch(
          fromId: 64,
          toId: 127,
          result: [_msg(64), _msg(127)],
        );
        await Future<void>.delayed(Duration.zero);

        final chunk = source.chunks[1]!;
        expect(chunk.isAbsentSlot(0), isFalse);
        expect(chunk.isAbsentSlot(63), isFalse);
        expect(chunk.messages[0]!.id, 64);
        expect(chunk.messages[63]!.id, 127);
        for (var slot = 1; slot < 63; slot++) {
          expect(chunk.isAbsentSlot(slot), isTrue, reason: 'slot $slot');
        }
        expect(chunk.isFullyAbsent, isFalse);
        expect(chunk.absentSlotCount, 62);
      },
    );

    test(
      'invalidate clears absent masks then re-fetch can restore a slot',
      () async {
        final source = _RecordingDataSource(fetchResult: []);
        source.simulateFetch(fromId: 0, toId: 63, result: [_msg(5)]);
        await Future<void>.delayed(Duration.zero);
        expect(source.statusOf(10).isAbsent, isTrue);

        source.invalidate();
        expect(source.statusOf(10).isAbsent, isFalse);
        expect(source.statusOf(10).isDirty, isTrue);

        source.simulateFetch(fromId: 0, toId: 63, result: [_msg(5), _msg(10)]);
        await Future<void>.delayed(Duration.zero);

        expect(source.statusOf(10).isAbsent, isFalse);
        expect(source.getMessage(10), isNotNull);
        expect(source.statusOf(11).isAbsent, isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // upsertMessage clears absent bit on realtime insert
  // ---------------------------------------------------------------------------

  group('upsertMessage clears absent bit', () {
    test(
      'upsertMessage at a previously-absent slot clears the bit and '
      'statusOf returns valid',
      () {
        final source = _TestDataSource();
        // Force-mark slot 20 (id 20 in chunk 0) absent.
        source.upsertMessage(_msg(0)); // ensure chunk 0 exists & is valid
        final chunk = source.chunks[ChatScrollChunk.chunkOf(0)]!;
        chunk.messages[20] = null; // ensure slot is null
        chunk.markAbsentSlot(20);
        expect(source.statusOf(20), ChatMessageStatus.absent);

        // Now upsert a real message at id 20.
        source.upsertMessage(_msg(20));

        expect(source.statusOf(20), ChatMessageStatus.valid);
        expect(source.getMessage(20), isNotNull);
        expect(chunk.isAbsentSlot(20), isFalse);
      },
    );

    test(
      'upsertMessages at previously-absent slots clears their bits',
      () {
        final source = _TestDataSource();
        source.upsertMessage(_msg(0));
        final chunk = source.chunks[ChatScrollChunk.chunkOf(0)]!;
        for (final slot in [1, 2, 3]) {
          chunk.messages[slot] = null;
          chunk.markAbsentSlot(slot);
        }
        // Upsert messages 1, 2, 3 via upsertMessages.
        source.upsertMessages([_msg(1), _msg(2), _msg(3)]);
        for (final id in [1, 2, 3]) {
          expect(source.statusOf(id), ChatMessageStatus.valid);
          expect(chunk.isAbsentSlot(id), isFalse);
        }
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Test-only data source that lets the test inject a custom fetch result.
// ---------------------------------------------------------------------------

class _RecordingDataSource extends ChatDataSource {
  _RecordingDataSource({required List<IChatMessage> fetchResult})
      : _defaultResult = fetchResult;

  final List<IChatMessage> _defaultResult;

  // ignore: unused_field
  Completer<List<IChatMessage>>? _completer;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => _defaultResult;

  /// Directly inject a fetch result as if `fetchRange` returned [result]
  /// for the chunk(s) covering [fromId..toId].
  void simulateFetch({
    required int fromId,
    required int toId,
    required List<IChatMessage> result,
  }) {
    // Replicate exactly what ChatDataSource._executeFetch does so we can
    // test the absent-marking logic in isolation.
    final fromChunk = ChatScrollChunk.chunkOf(fromId);
    final toChunk = ChatScrollChunk.chunkOf(toId);

    // Ensure all chunks exist.
    for (var ci = fromChunk; ci <= toChunk; ci++) {
      chunks.putIfAbsent(ci, () => ChatScrollChunk(index: ci));
    }

    // Upsert returned messages.
    for (final msg in result) {
      final ci = ChatScrollChunk.chunkOf(msg.id);
      final chunk = chunks[ci]!;
      chunk.messages[msg.id - chunk.firstId] = msg;
    }

    // Absent-marking pass (mirrors the corrected _executeFetch logic).
    for (var ci = fromChunk; ci <= toChunk; ci++) {
      final chunk = chunks[ci]!;
      for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
        if (chunk.messages[slot] != null) continue;
        chunk.markAbsentSlot(slot);
      }

      chunk.status = ChatMessageStatus.valid;
    }
  }
}
