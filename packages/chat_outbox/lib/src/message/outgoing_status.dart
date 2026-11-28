import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:meta/meta.dart';

/// How far an outgoing message got: `preparing → uploading → publishing →
/// sent`, or [OutgoingStatus.failed], or [OutgoingStatus.cancelled].
///
/// The status is a projection of the message's publish job plus the tail
/// rebase step, not a store of its own: the job's journal is the truth.
/// Every pause and the wait for a publisher show as the stage the job is in
/// ([uploading] or [publishing]), so an interrupted message keeps reading as
/// sending. [cancelled] is the outbox's own status: the publish job of a
/// cancelled message no longer exists to report it.
///
/// The host's time pill reads it: a clock while [preparing], [uploading] or
/// [publishing], one check on [sent]. The second (read) check is the server's message status, which
/// the outbox does not know.
///
/// Equal by value: two statuses of the same form are equal, and two
/// [failed] statuses are equal when their failures are.
@immutable
sealed class OutgoingStatus {
  /// Preparing the media for upload (transcoding, resizing).
  const factory OutgoingStatus.preparing() = OutgoingStatus$Preparing;

  /// Uploading the media, or waiting to.
  const factory OutgoingStatus.uploading() = OutgoingStatus$Uploading;

  /// Asking the server to publish the message, a conflict's rebase and
  /// repeated send included.
  const factory OutgoingStatus.publishing() = OutgoingStatus$Publishing;

  /// The server accepted the message.
  const factory OutgoingStatus.sent() = OutgoingStatus$Sent;

  /// The message was not sent, for [failure]; it waits for the user's retry
  /// or delete.
  const factory OutgoingStatus.failed(OutgoingFailure failure) =
      OutgoingStatus$Failed;

  /// The user cancelled the message; its row is gone.
  const factory OutgoingStatus.cancelled() = OutgoingStatus$Cancelled;

  const OutgoingStatus._();

  /// The form's stable name, the one diagnostics events and debug snapshots
  /// carry: `preparing`, `uploading`, `publishing`, `sent`, `failed` or
  /// `cancelled`. A [failed] status's reason is its failure's
  /// [OutgoingFailure.name].
  String get name;

  @override
  String toString() => 'OutgoingStatus.$name()';
}

/// [OutgoingStatus.preparing].
final class OutgoingStatus$Preparing extends OutgoingStatus {
  /// The preparing status.
  const OutgoingStatus$Preparing() : super._();

  @override
  String get name => 'preparing';

  @override
  bool operator ==(Object other) => other is OutgoingStatus$Preparing;

  @override
  int get hashCode => (OutgoingStatus$Preparing).hashCode;
}

/// [OutgoingStatus.uploading].
final class OutgoingStatus$Uploading extends OutgoingStatus {
  /// The uploading status.
  const OutgoingStatus$Uploading() : super._();

  @override
  String get name => 'uploading';

  @override
  bool operator ==(Object other) => other is OutgoingStatus$Uploading;

  @override
  int get hashCode => (OutgoingStatus$Uploading).hashCode;
}

/// [OutgoingStatus.publishing].
final class OutgoingStatus$Publishing extends OutgoingStatus {
  /// The publishing status.
  const OutgoingStatus$Publishing() : super._();

  @override
  String get name => 'publishing';

  @override
  bool operator ==(Object other) => other is OutgoingStatus$Publishing;

  @override
  int get hashCode => (OutgoingStatus$Publishing).hashCode;
}

/// [OutgoingStatus.sent].
final class OutgoingStatus$Sent extends OutgoingStatus {
  /// The sent status.
  const OutgoingStatus$Sent() : super._();

  @override
  String get name => 'sent';

  @override
  bool operator ==(Object other) => other is OutgoingStatus$Sent;

  @override
  int get hashCode => (OutgoingStatus$Sent).hashCode;
}

/// [OutgoingStatus.failed].
final class OutgoingStatus$Failed extends OutgoingStatus {
  /// The failed status, for [failure].
  const OutgoingStatus$Failed(this.failure) : super._();

  /// Why the message was not sent.
  final OutgoingFailure failure;

  @override
  String get name => 'failed';

  @override
  bool operator ==(Object other) =>
      other is OutgoingStatus$Failed && other.failure == failure;

  @override
  int get hashCode => Object.hash(OutgoingStatus$Failed, failure);

  @override
  String toString() => 'OutgoingStatus.failed($failure)';
}

/// [OutgoingStatus.cancelled].
final class OutgoingStatus$Cancelled extends OutgoingStatus {
  /// The cancelled status.
  const OutgoingStatus$Cancelled() : super._();

  @override
  String get name => 'cancelled';

  @override
  bool operator ==(Object other) => other is OutgoingStatus$Cancelled;

  @override
  int get hashCode => (OutgoingStatus$Cancelled).hashCode;
}

/// Why an outgoing message was not sent: a closed set.
///
/// The outbox always fails an album as a unit, so any item's failure fails
/// the whole message with one of these. Equal by value.
@immutable
sealed class OutgoingFailure {
  /// The network failed and the job gave up.
  const factory OutgoingFailure.network() = OutgoingFailure$Network;

  /// The server rejected the publish for [reason], an opaque code from the
  /// host's sender (never shown to the user as is, never logged).
  const factory OutgoingFailure.rejected(String reason) =
      OutgoingFailure$Rejected;

  /// The server denied [action] in this chat; the host's `onDenied` hears of
  /// it too.
  const factory OutgoingFailure.denied(CapabilityAction action) =
      OutgoingFailure$Denied;

  /// A media source is gone (on the web, a file a reload could not keep);
  /// the host may ask the user for the file again and pass its bytes to the
  /// outbox's retry (`ChatOutbox.retry(..., sources:)`).
  const factory OutgoingFailure.sourceLost() = OutgoingFailure$SourceLost;

  /// A media item is larger than the server takes.
  const factory OutgoingFailure.tooLarge() = OutgoingFailure$TooLarge;

  /// Anything else, a payload that no longer decodes among them.
  const factory OutgoingFailure.unknown() = OutgoingFailure$Unknown;

  const OutgoingFailure._();

  /// The form's stable name, the reason diagnostics events and debug
  /// snapshots carry: `network`, `rejected`, `denied`, `sourceLost`,
  /// `tooLarge` or `unknown`. Never the rejection's reason code, which comes
  /// from the server.
  String get name;

  @override
  String toString() => 'OutgoingFailure.$name()';
}

/// [OutgoingFailure.network].
final class OutgoingFailure$Network extends OutgoingFailure {
  /// The network failure.
  const OutgoingFailure$Network() : super._();

  @override
  String get name => 'network';

  @override
  bool operator ==(Object other) => other is OutgoingFailure$Network;

  @override
  int get hashCode => (OutgoingFailure$Network).hashCode;
}

/// [OutgoingFailure.rejected].
final class OutgoingFailure$Rejected extends OutgoingFailure {
  /// The rejection, for [reason].
  const OutgoingFailure$Rejected(this.reason) : super._();

  /// The host sender's opaque rejection code.
  final String reason;

  @override
  String get name => 'rejected';

  @override
  bool operator ==(Object other) =>
      other is OutgoingFailure$Rejected && other.reason == reason;

  @override
  int get hashCode => Object.hash(OutgoingFailure$Rejected, reason);

  // The reason stays out: a toString may reach a log.
}

/// [OutgoingFailure.denied].
final class OutgoingFailure$Denied extends OutgoingFailure {
  /// The denial of [action].
  const OutgoingFailure$Denied(this.action) : super._();

  /// The action the server denied.
  final CapabilityAction action;

  @override
  String get name => 'denied';

  @override
  bool operator ==(Object other) =>
      other is OutgoingFailure$Denied && other.action == action;

  @override
  int get hashCode => Object.hash(OutgoingFailure$Denied, action);

  @override
  String toString() => 'OutgoingFailure.denied(${action.name})';
}

/// [OutgoingFailure.sourceLost].
final class OutgoingFailure$SourceLost extends OutgoingFailure {
  /// The lost source failure.
  const OutgoingFailure$SourceLost() : super._();

  @override
  String get name => 'sourceLost';

  @override
  bool operator ==(Object other) => other is OutgoingFailure$SourceLost;

  @override
  int get hashCode => (OutgoingFailure$SourceLost).hashCode;
}

/// [OutgoingFailure.tooLarge].
final class OutgoingFailure$TooLarge extends OutgoingFailure {
  /// The too large failure.
  const OutgoingFailure$TooLarge() : super._();

  @override
  String get name => 'tooLarge';

  @override
  bool operator ==(Object other) => other is OutgoingFailure$TooLarge;

  @override
  int get hashCode => (OutgoingFailure$TooLarge).hashCode;
}

/// [OutgoingFailure.unknown].
final class OutgoingFailure$Unknown extends OutgoingFailure {
  /// The unknown failure.
  const OutgoingFailure$Unknown() : super._();

  @override
  String get name => 'unknown';

  @override
  bool operator ==(Object other) => other is OutgoingFailure$Unknown;

  @override
  int get hashCode => (OutgoingFailure$Unknown).hashCode;
}
