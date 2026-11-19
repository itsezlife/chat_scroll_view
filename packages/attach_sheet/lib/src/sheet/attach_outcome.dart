import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:flutter/foundation.dart';

/// The **attach outcome**: what the sheet hands the host when it closes.
@immutable
sealed class AttachOutcome {
  const AttachOutcome._();

  /// The user closed the sheet without sending.
  const factory AttachOutcome.cancelled() = AttachOutcome$Cancelled;

  /// A host page finished with [payload], which the host reads.
  const factory AttachOutcome.custom(AttachPageId page, Object? payload) =
      AttachOutcome$Custom;
}

/// [AttachOutcome.cancelled].
final class AttachOutcome$Cancelled extends AttachOutcome {
  /// Closed without sending.
  const AttachOutcome$Cancelled() : super._();

  @override
  bool operator ==(Object other) => other is AttachOutcome$Cancelled;

  @override
  int get hashCode => (AttachOutcome$Cancelled).hashCode;

  @override
  String toString() => 'AttachOutcome.cancelled()';
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
