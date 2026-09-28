import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';

/// Sender-run policy that breaks the run at the **unread boundary**, so the
/// unread separator never sits inside a bubble cluster.
///
/// Wraps [delegate] and changes at most two rows while [boundary] holds an
/// id:
///
/// - the boundary row reports first-in-run;
/// - its present predecessor — the message whose
///   [ChatDataSource.getNextPresentMessage] is the boundary row — reports
///   last-in-run.
///
/// Every other row, and every row while [boundary] is `null`, gets
/// [delegate]'s layout unchanged. The break only adds run ends; a row the
/// delegate already ends keeps its flags, and [MessageRunLayout.extras]
/// passes through.
///
/// The break follows what the viewport paints. A boundary row that is not
/// loaded resolves to [MessageRunLayout.degenerate] through [delegate], and
/// its predecessor sees no loaded next neighbor, so neither changes until
/// the row loads. A confirmed-absent boundary id has no present successor
/// relation to break, so the neighbors around it cluster as the delegate
/// decides — the same case in which no separator is painted.
///
/// As a [Listenable] this policy is [boundary], plus [delegate] when that is
/// listenable too: [addListener] and [removeListener] register on them
/// directly, so duplicate registration follows their rules. A boundary set,
/// move, or clear therefore relayouts the viewport, and only the rows whose
/// flags flip — the old and new boundary rows and their predecessors —
/// rebuild.
///
/// Equality is identity of [boundary] and equality of [delegate], so a
/// widget rebuild that constructs a fresh policy over the same boundary does
/// not relayout.
@immutable
final class UnreadBoundarySenderRunLayout
    implements ChatSenderRunLayout, Listenable {
  /// Breaks [delegate]'s runs at the current value of [boundary].
  const UnreadBoundarySenderRunLayout({
    required this.boundary,
    this.delegate = DefaultChatSenderRunLayout.instance,
  });

  /// Message id of the boundary row; `null` means no break. The same
  /// listenable the viewport receives as [ChatScrollView.unreadBoundary].
  final ValueListenable<int?> boundary;

  /// Clustering policy for every row the break does not touch.
  final ChatSenderRunLayout delegate;

  @override
  MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  }) {
    final layout = delegate.resolve(
      dataSource: dataSource,
      messageId: messageId,
      groupBy: groupBy,
    );
    final boundaryId = boundary.value;
    if (boundaryId == null) return layout;
    final startsRun = messageId == boundaryId;
    final endsRun =
        messageId < boundaryId &&
        dataSource.getNextPresentMessage(messageId)?.id == boundaryId;
    if (!startsRun && !endsRun) return layout;
    return MessageRunLayout(
      isFirstInSenderRun: layout.isFirstInSenderRun || startsRun,
      isLastInSenderRun: layout.isLastInSenderRun || endsRun,
      extras: layout.extras,
    );
  }

  /// Registers [listener] on [boundary], and on [delegate] when it is a
  /// [Listenable].
  @override
  void addListener(VoidCallback listener) {
    boundary.addListener(listener);
    if (delegate case final Listenable delegate) {
      delegate.addListener(listener);
    }
  }

  /// Removes [listener] from [boundary], and from [delegate] when it is a
  /// [Listenable].
  @override
  void removeListener(VoidCallback listener) {
    boundary.removeListener(listener);
    if (delegate case final Listenable delegate) {
      delegate.removeListener(listener);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is UnreadBoundarySenderRunLayout &&
      identical(other.boundary, boundary) &&
      other.delegate == delegate;

  @override
  int get hashCode => Object.hash(identityHashCode(boundary), delegate);
}
