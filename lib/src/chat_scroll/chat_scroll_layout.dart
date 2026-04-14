import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';

/// Stateless helper for chunk layout, positioning, clamping, and eviction.
///
/// Extracted from [RenderChatScrollView] to eliminate the 3x duplicated
/// anchor-positioning code and make layout math testable in isolation.
class ChatScrollLayoutHelper {
  // --- Chunk render layout ---

  /// Layout all renders in [chunk], recomputing [chunk.height].
  /// Creates renders lazily via [builder] if missing.
  ///
  /// [bubbleMaxWidth] is the maximum width available for the message bubble
  /// (already constrained by content area and fraction limits).
  void layoutChunkRenders(
    ChatScrollChunk chunk,
    double bubbleMaxWidth,
    ChatMessageRenderFactory builder,
    int accessTick,
  ) {
    chunk.lastAccessTick = accessTick;
    var totalHeight = 0.0;
    for (var i = 0; i < ChatScrollChunk.kSize; i++) {
      final message = chunk.messages[i];
      var render = chunk.renders[i];
      if (render == null) {
        render = builder(message);
        chunk.renders[i] = render;
      }
      render.update(message, chunk.status);
      if (render.dirty) {
        render.height = render.performLayout(bubbleMaxWidth);
        render.invalidatePaint();
        render.dirty = false;
      }
      totalHeight += render.height;
    }
    chunk.height = totalHeight;
  }

  // --- Unified positioning (replaces 3 duplicates from v1) ---

  /// Position all chunks relative to the current anchor state.
  ///
  /// This is the single copy of the "compute beforeAnchorHeight,
  /// set chunk.offsetY, fan out up/down" logic that was duplicated
  /// 3 times in v1 (_performLayoutImpl, _repositionChunks,
  /// _repositionAfterClamp).
  ///
  /// [layoutChunk] is called for chunks that need render layout.
  /// Pass `null` for reposition-only (scroll path).
  ///
  /// Returns `false` if the anchor chunk is missing (caller should bail).
  bool positionFromAnchor({
    required ChatScrollController controller,
    required ChatDataSource dataSource,
    required int layoutMinChunk,
    required int layoutMaxChunk,
    void Function(ChatScrollChunk chunk)? layoutChunk,
  }) {
    final anchorId = controller.anchorMessageId;
    final anchorOffset = controller.anchorPixelOffset;
    final anchorChunkIndex = ChatScrollChunk.chunkOf(anchorId);
    final anchorChunk = dataSource.chunks[anchorChunkIndex];
    if (anchorChunk == null) return false;

    if (layoutChunk != null) layoutChunk(anchorChunk);

    // Compute height of messages before anchor in its chunk.
    var beforeAnchorHeight = 0.0;
    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    for (var i = 0; i < anchorLocalIndex; i++) {
      final r = anchorChunk.renders[i];
      if (r != null) beforeAnchorHeight += r.height;
    }
    anchorChunk.offsetY = anchorOffset - beforeAnchorHeight;
    _positionChunkRenders(anchorChunk);

    // Fan out downward.
    var y = anchorChunk.offsetY + anchorChunk.height;
    for (var ci = anchorChunkIndex + 1; ci <= layoutMaxChunk; ci++) {
      final chunk = dataSource.chunks[ci];
      if (chunk == null) break;
      if (layoutChunk != null) layoutChunk(chunk);
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
      y += chunk.height;
    }

    // Fan out upward.
    y = anchorChunk.offsetY;
    for (var ci = anchorChunkIndex - 1; ci >= layoutMinChunk; ci--) {
      final chunk = dataSource.chunks[ci];
      if (chunk == null) break;
      if (layoutChunk != null) layoutChunk(chunk);
      y -= chunk.height;
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
    }

    return true;
  }

  /// Set [offsetY] on each render in [chunk] based on [chunk.offsetY].
  void _positionChunkRenders(ChatScrollChunk chunk) {
    var y = chunk.offsetY;
    for (var i = 0; i < ChatScrollChunk.kSize; i++) {
      final render = chunk.renders[i];
      if (render == null) continue;
      render.offsetY = y;
      y += render.height;
    }
  }

  // --- Anchor renormalization ---

  /// If the anchor message drifted beyond [cacheExtent] from the viewport,
  /// silently reassign to the first visible message.
  void renormalizeAnchor(
    ChatScrollController controller,
    ChatDataSource dataSource,
    int layoutMinChunk,
    int layoutMaxChunk,
    double cacheExtent,
    double viewportHeight,
  ) {
    final anchorId = controller.anchorMessageId;
    final anchorChunkIndex = ChatScrollChunk.chunkOf(anchorId);
    final anchorChunk = dataSource.chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    final anchorRender = anchorChunk.renders[anchorLocalIndex];
    if (anchorRender == null) return;

    final anchorTop = anchorRender.offsetY;
    final anchorBottom = anchorTop + anchorRender.height;

    // Anchor still within viewport + cacheExtent — nothing to do.
    if (anchorBottom >= -cacheExtent &&
        anchorTop <= viewportHeight + cacheExtent) {
      return;
    }

    // Find first message whose bottom edge is below viewport top.
    for (var ci = layoutMinChunk; ci <= layoutMaxChunk; ci++) {
      final chunk = dataSource.chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null || render.isEmpty) continue;
        if (render.offsetY + render.height > 0) {
          controller.reassignAnchor(chunk.firstId + i, render.offsetY);
          return;
        }
      }
    }
  }

  // --- Boundary clamping ---

  /// Clamp scroll so content doesn't detach from viewport edges
  /// when the conversation boundary has been reached.
  ///
  /// Returns `true` if fling should be cancelled (boundary was hit).
  bool clampScrollBoundaries(
    ChatScrollController controller,
    ChatDataSource dataSource,
    int layoutMinChunk,
    int layoutMaxChunk,
    double viewportHeight,
  ) {
    var cancelFling = false;

    // Bottom: pin content bottom to viewport bottom.
    if (controller.reachedNewest && controller.newestKnownId != null) {
      final newestChunkIndex =
          ChatScrollChunk.chunkOf(controller.newestKnownId!);
      if (newestChunkIndex <= layoutMaxChunk) {
        final lastChunk = dataSource.chunks[layoutMaxChunk];
        if (lastChunk != null) {
          final contentBottom = lastChunk.offsetY + lastChunk.height;
          if (contentBottom < viewportHeight) {
            final correction = viewportHeight - contentBottom;
            controller.applyScrollDelta(correction);
            positionFromAnchor(
              controller: controller,
              dataSource: dataSource,
              layoutMinChunk: layoutMinChunk,
              layoutMaxChunk: layoutMaxChunk,
            );
            cancelFling = true;
          }
        }
      }
    }

    // Top: pin content top to viewport top.
    if (controller.reachedOldest && controller.oldestKnownId != null) {
      final oldestChunkIndex =
          ChatScrollChunk.chunkOf(controller.oldestKnownId!);
      if (oldestChunkIndex >= layoutMinChunk) {
        final firstChunk = dataSource.chunks[layoutMinChunk];
        if (firstChunk != null) {
          final contentTop = firstChunk.offsetY;
          if (contentTop > 0) {
            controller.applyScrollDelta(-contentTop);
            positionFromAnchor(
              controller: controller,
              dataSource: dataSource,
              layoutMinChunk: layoutMinChunk,
              layoutMaxChunk: layoutMaxChunk,
            );
            cancelFling = true;
          }
        }
      }
    }

    return cancelFling;
  }

  // --- LRU chunk eviction ---

  /// Evict old chunks if we exceed [maxChunks].
  /// Never evict chunks in the current layout range.
  void evictChunks(
    Map<int, ChatScrollChunk> chunks,
    int maxChunks,
    int layoutMinChunk,
    int layoutMaxChunk,
  ) {
    while (chunks.length > maxChunks) {
      ChatScrollChunk? oldest;
      for (final chunk in chunks.values) {
        if (chunk.index >= layoutMinChunk &&
            chunk.index <= layoutMaxChunk) {
          continue;
        }
        if (oldest == null ||
            chunk.lastAccessTick < oldest.lastAccessTick) {
          oldest = chunk;
        }
      }
      if (oldest == null) break;
      oldest.dispose();
      chunks.remove(oldest.index);
    }
  }
}
