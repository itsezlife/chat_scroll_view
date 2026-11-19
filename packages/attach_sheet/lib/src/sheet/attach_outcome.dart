import 'package:flutter/foundation.dart';

/// The **attach outcome**: what the sheet hands the host when it closes.
@immutable
sealed class AttachOutcome {
  const AttachOutcome._();

  /// The user closed the sheet without sending.
  const factory AttachOutcome.cancelled() = AttachOutcome$Cancelled;
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
