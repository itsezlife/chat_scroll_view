import 'package:chatscrollview/src/chat_scroll_view_common.dart';
import 'package:chatscrollview/src/v2/chat_message_render.dart';
import 'package:meta/meta.dart';

/// Chunk of chat messages used for pagination and rendering.
///
/// Holds both message data and render objects in parallel fixed-size arrays.
/// Chunk index is calculated by shifting the message id right by [kBits].
@internal
class ChatScrollChunk {
  static const int kBits = 6;
  static const int kSize = 64; // 1 << kBits

  /// Get the chunk index for a given message id.
  /// Dart's `>>` is arithmetic shift — works correctly for negative IDs.
  static int chunkOf(int messageId) => messageId >> kBits;

  /// Get the first message id for a given chunk index.
  static int firstIdOf(int chunkIndex) => chunkIndex << kBits;

  ChatScrollChunk({required this.index})
    : messages = List<IChatMessage?>.filled(kSize, null, growable: false),
      renders = List<ChatMessageRender?>.filled(kSize, null, growable: false),
      firstId = firstIdOf(index);

  /// The chunk index, calculated as messageId >> kBits.
  /// Can be negative for messages with negative IDs.
  final int index;

  /// The first message id in this chunk (inclusive).
  final int firstId;

  /// The last message id in this chunk (inclusive).
  int get lastId => firstId + kSize - 1;

  /// Message data — populated from fetch results.
  final List<IChatMessage?> messages;

  /// Render objects — created lazily by the viewport.
  final List<ChatMessageRender?> renders;

  /// Data status (dirty, fetching, error, valid).
  ChatMessageStatus status = ChatMessageStatus.dirty;

  /// Monotonic access tick — bumped on layout to track LRU order.
  int lastAccessTick = 0;

  /// Y offset of this chunk's first message within the viewport.
  double offsetY = 0.0;

  /// Total height of all laid-out messages in this chunk.
  double height = 0.0;

  /// Mark all renders in this chunk as dirty, causing them to be re-laid out
  /// and re-painted on the next frame.
  void markRendersDirty() {
    for (final render in renders) {
      if (render == null) continue;
      render.dirty = true;
      render.invalidatePaint();
    }
  }

  /// Dispose all renders in this chunk and clear the list.
  void disposeRenders() {
    for (var i = 0; i < renders.length; i++) {
      renders[i]?.dispose();
      renders[i] = null;
    }
  }
}
