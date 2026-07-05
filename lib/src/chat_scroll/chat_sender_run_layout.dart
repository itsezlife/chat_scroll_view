import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/foundation.dart';

/// Bucket-scoped first/last position within a contiguous same-sender run.
///
/// A **sender run** is the maximal chain of **present** messages (confirmed
/// loaded, not absent or pending removal) that share the same [IChatMessage.sender]
/// within one [Object] bucket from [ChatScrollView.groupBy]. When grouping is
/// off (`groupBy == null`), the bucket is unbounded — runs span the whole
/// conversation until sender changes or an absent slot breaks the chain.
///
/// **Who computes this:** [RenderChatScrollView] calls
/// [ChatSenderRunLayout.resolve] during layout and passes the result into
/// [ChatChildManager.buildChild]. [ChatScrollElement] stores [MessageRunLayout]
/// in the skip-rebuild cache (value equality). Integrators MUST consume
/// [MessageRunLayout] from [ChatMessageBuilder] — walking
/// [ChatDataSource.getPreviousPresentMessage] inside the builder bypasses the
/// cache and leaves position-specific chrome stale after delete, insert, or
/// neighbor sender edits when [identical] message instances are reused.
///
/// **Policy agnostic:** the package exposes both ends of the run; whether
/// avatar, sender label, or bubble tail attach to first, last, or both is
/// integrator/demo choice ([DemoMessageBubble] uses last-in-run / Telegram-style).
@immutable
class MessageRunLayout {
  /// Position flags for a loaded message within its effective bucket.
  ///
  /// Both flags may be `true` for a solitary message in its run (including
  /// after a bucket break splits one sender into two one-message runs).
  const MessageRunLayout({
    required this.isFirstInSenderRun,
    required this.isLastInSenderRun,
  });

  /// Placeholder when [ChatSenderRunLayout.resolve] runs for an unloaded slot.
  ///
  /// Returns both flags `true` so builders that gate chrome on either end still
  /// render a complete row for shimmer/loading — conservative default rather
  /// than hiding avatar/sender before data arrives.
  const MessageRunLayout.degenerate()
    : isFirstInSenderRun = true,
      isLastInSenderRun = true;

  /// `true` when there is no previous **present** neighbor in the same
  /// sender+bucket run (conversation-order walk via
  /// [ChatDataSource.getPreviousPresentMessage], skipping confirmed-absent ids).
  final bool isFirstInSenderRun;

  /// `true` when there is no next **present** neighbor in the same sender+bucket
  /// run ([ChatDataSource.getNextPresentMessage]).
  final bool isLastInSenderRun;

  @override
  bool operator ==(Object other) =>
      other is MessageRunLayout &&
      other.isFirstInSenderRun == isFirstInSenderRun &&
      other.isLastInSenderRun == isLastInSenderRun;

  @override
  int get hashCode => Object.hash(isFirstInSenderRun, isLastInSenderRun);
}

/// Resolves [MessageRunLayout] from live [ChatDataSource] neighbors.
///
/// Called from the render object on every [ChatChildManager.buildChild] for a
/// loaded message id — not from [ChatMessageBuilder] — so neighbor changes
/// after mutations invalidate the skip-rebuild cache even when message
/// identity is unchanged.
abstract final class ChatSenderRunLayout {
  /// Computes first/last-in-run for [messageId] at layout time.
  ///
  /// **Neighbor probes:** uses [ChatDataSource.getPreviousPresentMessage] and
  /// [ChatDataSource.getNextPresentMessage] only — never raw `id ± 1`, which
  /// would treat confirmed-absent holes as loaded neighbors and mis-classify
  /// runs after delete.
  ///
  /// **Bucket rule:** when [groupBy] is non-null, prev/next must share both
  /// [IChatMessage.sender] and the same bucket key (`groupBy(message)`) to
  /// count as the same run. A calendar-day separator therefore ends a run even
  /// when the same person sent on consecutive days.
  ///
  /// **Grouping off:** when [groupBy] is `null`, sender equality alone defines
  /// the run; bucket keys are ignored.
  ///
  /// **Unloaded slot:** when [ChatDataSource.getMessage] returns `null`,
  /// returns [MessageRunLayout.degenerate] — the element may still build a
  /// shimmer row before fetch completes.
  static MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  }) {
    final message = dataSource.getMessage(messageId);
    if (message == null) {
      return const MessageRunLayout.degenerate();
    }

    final bucket = groupBy?.call(message);
    // Present-neighbor walks skip confirmed-absent ids (deleted / staging).
    final prev = dataSource.getPreviousPresentMessage(messageId);
    final next = dataSource.getNextPresentMessage(messageId);

    // First when no prev, or prev is different sender or different bucket.
    final isFirst =
        prev == null ||
        !_sameSenderRun(
          message: message,
          neighbor: prev,
          bucket: bucket,
          neighborBucket: groupBy?.call(prev),
          groupBy: groupBy,
        );

    // Last when no next, or next is different sender or different bucket.
    final isLast =
        next == null ||
        !_sameSenderRun(
          message: message,
          neighbor: next,
          bucket: bucket,
          neighborBucket: groupBy?.call(next),
          groupBy: groupBy,
        );

    return MessageRunLayout(
      isFirstInSenderRun: isFirst,
      isLastInSenderRun: isLast,
    );
  }

  /// Whether [neighbor] continues the same sender run as [message].
  ///
  /// Sender mismatch always breaks the run. When [groupBy] is null, sender
  /// match is sufficient. When grouping is on, bucket keys must compare equal
  /// with `==` — custom groupers must return stable, equatable keys (e.g.
  /// truncated [DateTime], `(year, month)` records).
  static bool _sameSenderRun({
    required IChatMessage message,
    required IChatMessage neighbor,
    required Object? bucket,
    required Object? neighborBucket,
    required Object? Function(IChatMessage)? groupBy,
  }) {
    if (message.sender != neighbor.sender) return false;
    if (groupBy == null) return true;
    return bucket == neighborBucket;
  }
}
