import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';

/// Per-message status lookup for [ChatDataSource].
///
/// Fetch status is tracked per chunk; this resolves the owning chunk for [id]
/// and returns its status, or [ChatMessageStatus.dirty] when the chunk has not
/// been loaded yet.
extension ChatDataSourceStatus on ChatDataSource {
  ChatMessageStatus statusOf(int id) =>
      chunks[ChatScrollChunk.chunkOf(id)]?.status ?? ChatMessageStatus.dirty;
}
