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
/// [RenderChatScrollView] calls [ChatSenderRunLayout.resolve] during layout
/// and passes the result into [ChatChildManager.buildChild].
/// [ChatScrollElement] stores [MessageRunLayout] in the skip-rebuild cache
/// (value equality, including [extras]). Integrators MUST consume
/// [MessageRunLayout] from [ChatMessageBuilder]. Walking neighbors inside the
/// builder bypasses the cache and leaves chrome stale after mutations when
/// [identical] message instances are reused.
///
/// Whether avatar, sender label, or bubble tail attach to first, last, or both
/// is integrator choice.
///
/// [extras] is host chrome that rides skip-rebuild equality. It is not a
/// clustering input. The package default leaves it `null`. Hosts that need a
/// typed bag wrap [DefaultChatSenderRunLayout] (or a custom policy), close
/// over host state, set [extras], and cast in the builder. Give [extras] a
/// real [operator ==]; identity-only or mutable bags never miss the cache.
@immutable
class MessageRunLayout {
  /// Position flags for a loaded message within its effective run.
  ///
  /// Both flags may be `true` for a solitary message (including after a
  /// policy break splits one sender into two one-message runs).
  ///
  /// [extras] is optional host chrome for the skip-rebuild cache (default
  /// `null`). It does not affect clustering.
  const MessageRunLayout({
    required this.isFirstInSenderRun,
    required this.isLastInSenderRun,
    this.extras,
  });

  /// Placeholder when [ChatSenderRunLayout.resolve] runs for an unloaded slot.
  ///
  /// Both flags are `true` so builders that gate chrome on either end still
  /// draw a complete shimmer/loading row instead of hiding avatar/sender
  /// before data arrives. [extras] is always `null`.
  const MessageRunLayout.degenerate()
    : isFirstInSenderRun = true,
      isLastInSenderRun = true,
      extras = null;

  /// `true` when there is no previous **present** neighbor in the same run
  /// ([ChatDataSource.getPreviousPresentMessage]).
  final bool isFirstInSenderRun;

  /// `true` when there is no next **present** neighbor in the same run
  /// ([ChatDataSource.getNextPresentMessage]).
  final bool isLastInSenderRun;

  /// Host chrome for skip-rebuild. Not clustering.
  ///
  /// Package default and [MessageRunLayout.degenerate] leave this `null`.
  /// Hosts cast to a typed bag in [ChatMessageBuilder]. The bag type must
  /// implement [operator ==] / [hashCode] so only flipped rows reinflate.
  final Object? extras;

  @override
  bool operator ==(Object other) =>
      other is MessageRunLayout &&
      other.isFirstInSenderRun == isFirstInSenderRun &&
      other.isLastInSenderRun == isLastInSenderRun &&
      other.extras == extras;

  @override
  int get hashCode =>
      Object.hash(isFirstInSenderRun, isLastInSenderRun, extras);
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
