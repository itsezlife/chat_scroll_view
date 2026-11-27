import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
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
  /// surface that prepared before closing (the confirm box), by item.
  const factory AttachOutcome.send(
    SendRequest request, {
    Map<AttachItemId, PreparedMedia> prepared,
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
  const AttachOutcome$Send(this.request, {this.prepared = const {}})
    : super._();

  /// What to send.
  final SendRequest request;

  /// The prepared outputs by item; empty when the host prepares itself.
  final Map<AttachItemId, PreparedMedia> prepared;

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
