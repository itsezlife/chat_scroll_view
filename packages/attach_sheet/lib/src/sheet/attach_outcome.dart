import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:mpx_core/mpx_core.dart' show PreparedMedia;

/// The **attach outcome**: what the sheet hands the host when it closes.
@immutable
sealed class AttachOutcome {
  const AttachOutcome._();

  /// The user closed the sheet without sending; [caption] goes back to the
  /// composer.
  const factory AttachOutcome.cancelled([RichText caption]) =
      AttachOutcome$Cancelled;

  /// The user sent [request]: the host plans it (`planSend`) and makes the
  /// messages, and clears the composer. [prepared] holds the outputs of a
  /// surface that prepared before closing (the confirm box), by item;
  /// [origins] the send origins of the items whose thumbnail was on screen.
  const factory AttachOutcome.send(
    SendRequest request, {
    Map<AttachItemId, PreparedMedia> prepared,
    Map<AttachItemId, Rect> origins,
  }) = AttachOutcome$Send;

  /// A host page finished with [payload], which the host reads.
  const factory AttachOutcome.custom(AttachPageId page, Object? payload) =
      AttachOutcome$Custom;
}

/// [AttachOutcome.cancelled].
final class AttachOutcome$Cancelled extends AttachOutcome {
  /// Closed without sending.
  const AttachOutcome$Cancelled([this.caption = RichText.empty]) : super._();

  /// The caption as it was, for the composer.
  final RichText caption;

  @override
  bool operator ==(Object other) =>
      other is AttachOutcome$Cancelled && other.caption == caption;

  @override
  int get hashCode => Object.hash(AttachOutcome$Cancelled, caption);

  @override
  String toString() => 'AttachOutcome.cancelled(${caption.plain})';
}

/// [AttachOutcome.send].
final class AttachOutcome$Send extends AttachOutcome {
  /// Sent [request].
  const AttachOutcome$Send(
    this.request, {
    this.prepared = const {},
    this.origins = const {},
  }) : super._();

  /// What to send.
  final SendRequest request;

  /// The prepared outputs by item; empty when the host prepares itself.
  final Map<AttachItemId, PreparedMedia> prepared;

  /// The **send origins**: the global rect of each item's thumbnail as the
  /// user sent, for the items whose thumbnail was on screen then; an item
  /// scrolled off, or sent from a surface that draws no thumbnail of it,
  /// has none.
  ///
  /// The host hands them on with each planned send, by [originsOf], so the
  /// message's media can fly in from where the user picked it.
  final Map<AttachItemId, Rect> origins;

  /// The send origins of [send]'s items by their order in it, null for an
  /// item without one; empty for a text.
  ///
  /// The order is the planned send's, not the request's: the plan may
  /// split and reorder the request's items, and the outbox keys the rects
  /// by the ids it gives the planned send's items in order.
  List<Rect?> originsOf(PlannedSend send) => switch (send) {
    PlannedSend$Single(:final item) => [origins[item.id]],
    PlannedSend$Group(:final items) => [
      for (final item in items) origins[item.id],
    ],
    PlannedSend$Text() => const [],
  };

  @override
  String toString() => 'AttachOutcome.send(${request.items.length} items)';
}

/// [AttachOutcome.custom].
final class AttachOutcome$Custom extends AttachOutcome {
  /// [page] finished with [payload].
  const AttachOutcome$Custom(this.page, this.payload) : super._();

  /// The host page that finished.
  final AttachPageId page;

  /// What it finished with; compared by `==`.
  final Object? payload;

  @override
  bool operator ==(Object other) =>
      other is AttachOutcome$Custom &&
      other.page == page &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(page, payload);

  @override
  String toString() => 'AttachOutcome.custom($page, $payload)';
}
