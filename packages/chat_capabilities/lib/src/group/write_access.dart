import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:meta/meta.dart';

/// Whether the user may write in the chat at all, and if not, what occupies
/// the input row in its place.
///
/// The input row is replaced, never disabled: each form other than
/// [WriteAccess.canWrite] names the panel the composer shows instead.
@immutable
sealed class WriteAccess {
  const WriteAccess._();

  /// The user may write; the input row is the text field.
  const factory WriteAccess.canWrite() = WriteAccess$CanWrite;

  /// The user reads only (a broadcast); the row shows the mute bar.
  const factory WriteAccess.readOnly() = WriteAccess$ReadOnly;

  /// The user must join first; the row shows a join bar.
  const factory WriteAccess.join() = WriteAccess$Join;

  /// The user must ask to join; the row shows a request bar.
  const factory WriteAccess.requestToJoin() = WriteAccess$RequestToJoin;

  /// Writing is denied for [reason]; the row shows the restriction bar.
  const factory WriteAccess.restricted(DenialReason reason) =
      WriteAccess$Restricted;

  /// A host form the packages do not model, by the host's [tag]; the host
  /// draws its panel.
  const factory WriteAccess.custom(String tag) = WriteAccess$Custom;

  /// Whether the user may write.
  bool get canWrite => false;

  /// Why the user may not write, as a host's text for the replacing panel
  /// is asked with: a restriction's own reason, otherwise
  /// [DenialReason.noWriteAccess] of this form; null for [canWrite].
  DenialReason? get denialReason => switch (this) {
    WriteAccess$CanWrite() => null,
    WriteAccess$Restricted(:final reason) => reason,
    _ => DenialReason.noWriteAccess(this),
  };

  /// The form alone, for diagnostics events: `canWrite`, `readOnly`,
  /// `join`, `requestToJoin`, `restricted` or `custom`. A restriction's
  /// reason and a host form's tag are left out, so the field stays short.
  String get diagnosticForm => switch (this) {
    WriteAccess$CanWrite() => 'canWrite',
    WriteAccess$ReadOnly() => 'readOnly',
    WriteAccess$Join() => 'join',
    WriteAccess$RequestToJoin() => 'requestToJoin',
    WriteAccess$Restricted() => 'restricted',
    WriteAccess$Custom() => 'custom',
  };
}

/// [WriteAccess.canWrite].
final class WriteAccess$CanWrite extends WriteAccess {
  /// The user may write.
  const WriteAccess$CanWrite() : super._();

  @override
  bool get canWrite => true;

  @override
  bool operator ==(Object other) => other is WriteAccess$CanWrite;

  @override
  int get hashCode => (WriteAccess$CanWrite).hashCode;

  @override
  String toString() => 'canWrite';
}

/// [WriteAccess.readOnly].
final class WriteAccess$ReadOnly extends WriteAccess {
  /// The user reads only.
  const WriteAccess$ReadOnly() : super._();

  @override
  bool operator ==(Object other) => other is WriteAccess$ReadOnly;

  @override
  int get hashCode => (WriteAccess$ReadOnly).hashCode;

  @override
  String toString() => 'readOnly';
}

/// [WriteAccess.join].
final class WriteAccess$Join extends WriteAccess {
  /// The user must join.
  const WriteAccess$Join() : super._();

  @override
  bool operator ==(Object other) => other is WriteAccess$Join;

  @override
  int get hashCode => (WriteAccess$Join).hashCode;

  @override
  String toString() => 'join';
}

/// [WriteAccess.requestToJoin].
final class WriteAccess$RequestToJoin extends WriteAccess {
  /// The user must ask to join.
  const WriteAccess$RequestToJoin() : super._();

  @override
  bool operator ==(Object other) => other is WriteAccess$RequestToJoin;

  @override
  int get hashCode => (WriteAccess$RequestToJoin).hashCode;

  @override
  String toString() => 'requestToJoin';
}

/// [WriteAccess.restricted].
final class WriteAccess$Restricted extends WriteAccess {
  /// Writing is denied.
  const WriteAccess$Restricted(this.reason) : super._();

  /// Why writing is denied.
  final DenialReason reason;

  @override
  bool operator ==(Object other) =>
      other is WriteAccess$Restricted && other.reason == reason;

  @override
  int get hashCode => Object.hash(WriteAccess$Restricted, reason);

  @override
  String toString() => 'restricted($reason)';
}

/// [WriteAccess.custom].
final class WriteAccess$Custom extends WriteAccess {
  /// A host form.
  const WriteAccess$Custom(this.tag) : super._();

  /// The host's tag for the form.
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is WriteAccess$Custom && other.tag == tag;

  @override
  int get hashCode => Object.hash(WriteAccess$Custom, tag);

  @override
  String toString() => 'custom($tag)';
}
