import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
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
  }) async =>
      const <IChatMessage>[];
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
      source = _TestDataSource();
      source.upsertMessage(_msg(100));
      source.upsertMessage(_msg(199));
    });

    test('getMessage(100) returns message when 101–198 are null in chunk 1', () {
      final m = source.getMessage(100);
      expect(m, isNotNull);
      expect(m!.id, 100);
      expect(source.getMessage(101), isNull);
      expect(source.getMessage(150), isNull);
      expect(source.getMessage(198), isNull);
      expect(source.getMessage(199)!.id, 199);
    });

    test('slot assertion fires when chunk is stored at wrong index', () {
      // Chunk for index 0 (firstId 0) stored under key 1 — simulates corruption.
      source.chunks[1] = ChatScrollChunk(index: 0);

      expect(
        () => source.getMessage(64),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
