import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/foundation.dart';

/// Bucket-scoped first/last position within a contiguous same-sender run.
///
/// A **sender run** is the maximal chain of **present** messages that the
/// active [ChatSenderRunLayout] policy treats as one cluster. The package
/// default ([DefaultChatSenderRunLayout]) groups by same
/// [IChatMessage.sender], optional [ChatScrollView.groupBy] bucket, and an
/// optional `|createdAt|` window.
///
/// **Who computes this:** [RenderChatScrollView] calls
/// [ChatSenderRunLayout.resolve] during layout and passes the result into
/// [ChatChildManager.buildChild]. [ChatScrollElement] stores [MessageRunLayout]
/// in the skip-rebuild cache (value equality). Integrators MUST consume
/// [MessageRunLayout] from [ChatMessageBuilder] — walking neighbors inside the
/// builder bypasses the cache and leaves chrome stale after mutations when
/// [identical] message instances are reused.
///
/// **Policy agnostic:** whether avatar, sender label, or bubble tail attach to
/// first, last, or both is integrator/demo choice.
@immutable
class MessageRunLayout {
  /// Position flags for a loaded message within its effective run.
  ///
  /// Both flags may be `true` for a solitary message (including after a
  /// policy break splits one sender into two one-message runs).
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

  /// `true` when there is no previous **present** neighbor in the same run
  /// ([ChatDataSource.getPreviousPresentMessage]).
  final bool isFirstInSenderRun;

  /// `true` when there is no next **present** neighbor in the same run
  /// ([ChatDataSource.getNextPresentMessage]).
  final bool isLastInSenderRun;

  @override
  bool operator ==(Object other) =>
      other is MessageRunLayout &&
      other.isFirstInSenderRun == isFirstInSenderRun &&
      other.isLastInSenderRun == isLastInSenderRun;

  @override
  int get hashCode => Object.hash(isFirstInSenderRun, isLastInSenderRun);
}

/// Host-owned policy that decides first/last-in-run for each message id.
///
/// Inject via [ChatScrollView.senderRunLayout]. The viewport calls [resolve]
/// from the render object on every [ChatChildManager.buildChild] — never from
/// [ChatMessageBuilder] — so neighbor changes invalidate the skip-rebuild
/// cache even when message identity is unchanged.
///
/// Implement this to replace sender / time / bucket clustering without forking
/// the package. Prefer immutable implementations with value [operator ==] so
/// parent rebuilds with an equal policy do not force relayout.
abstract interface class ChatSenderRunLayout {
  /// Computes first/last-in-run for [messageId] at layout time.
  ///
  /// [groupBy] is the viewport’s effective grouping callback (`null` when day
  /// separators are off). Policies may ignore it.
  ///
  /// When [ChatDataSource.getMessage] returns `null`, return
  /// [MessageRunLayout.degenerate].
  MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  });
}

/// Package default: same sender + optional [groupBy] bucket + optional
/// `|createdAt|` window (default 5 minutes).
///
/// Pass a custom instance to tune [maxClusterGap], or implement
/// [ChatSenderRunLayout] for a different clustering model.
@immutable
class DefaultChatSenderRunLayout implements ChatSenderRunLayout {
  /// Creates the default clustering policy.
  ///
  /// [maxClusterGap] — max `|createdAt|` between present same-sender neighbors
  /// that may share a run. Default is 5 minutes. Pass `null` to disable the
  /// time window (sender + [groupBy] bucket only).
  const DefaultChatSenderRunLayout({this.maxClusterGap = defaultMaxClusterGap});

  /// Default cluster window (5 minutes).
  static const Duration defaultMaxClusterGap = Duration(minutes: 5);

  /// Shared const instance with [defaultMaxClusterGap].
  static const DefaultChatSenderRunLayout instance =
      DefaultChatSenderRunLayout();

  /// Max `|createdAt|` for same-sender neighbors to stay in one run.
  /// `null` disables the time window.
  final Duration? maxClusterGap;

  @override
  MessageRunLayout resolve({
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

    final isFirst =
        prev == null ||
        !_sameSenderRun(
          message: message,
          neighbor: prev,
          bucket: bucket,
          neighborBucket: groupBy?.call(prev),
          groupBy: groupBy,
        );

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
  /// Sender mismatch always breaks. When [groupBy] is null, sender match is
  /// sufficient (subject to [maxClusterGap]). When grouping is on, bucket keys
  /// must compare equal with `==`.
  bool _sameSenderRun({
    required IChatMessage message,
    required IChatMessage neighbor,
    required Object? bucket,
    required Object? neighborBucket,
    required Object? Function(IChatMessage)? groupBy,
  }) {
    if (message.sender != neighbor.sender) return false;
    final gap = maxClusterGap;
    if (gap != null) {
      final delta = message.createdAt.difference(neighbor.createdAt).abs();
      if (delta > gap) return false;
    }
    if (groupBy == null) return true;
    return bucket == neighborBucket;
  }

  @override
  bool operator ==(Object other) =>
      other is DefaultChatSenderRunLayout &&
      other.maxClusterGap == maxClusterGap;

  @override
  int get hashCode => maxClusterGap.hashCode;
}
