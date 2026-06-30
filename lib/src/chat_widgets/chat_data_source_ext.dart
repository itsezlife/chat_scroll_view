import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';

/// Per-message status lookup for [ChatDataSource].
///
/// Fetch status is tracked per chunk; this resolves the owning chunk for [id]
/// and returns its status, or [ChatMessageStatus.dirty] when the chunk has not
/// been loaded yet.
///
/// **Lint**: [ChatMessageStatus] is an `extension type` over `int` — compare
/// using `.isDirty`, `.isError`, etc., not raw integers.
extension ChatDataSourceStatus on ChatDataSource {
  /// Per-slot status for [id].
  ///
  /// Three-branch decision tree:
  ///
  /// 1. **Chunk not loaded** → returns `dirty` (chunk is missing from cache).
  /// 2. **Slot confirmed absent** → returns `absent` (server confirmed this ID
  ///    does not exist; determined by the absent-marking pass after a successful
  ///    `fetchRange`). Fan-out skips absent IDs; they render at zero height.
  /// 3. **Otherwise** → returns the chunk's status (`valid`, `dirty`,
  ///    `fetching`, or `error`).
  ChatMessageStatus statusOf(int id) {
    final chunk = chunks[ChatScrollChunk.chunkOf(id)];
    if (chunk == null) return ChatMessageStatus.dirty;
    if (chunk.isAbsentSlot(id - chunk.firstId)) return ChatMessageStatus.absent;
    return chunk.status;
  }
}
