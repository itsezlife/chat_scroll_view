import 'package:chat_capabilities/src/group/write_access.dart';
import 'package:content_model/content_model.dart' show ChatEvent;
import 'package:meta/meta.dart';

/// One action's outcome in the chat capabilities: allowed, or denied with a
/// [DenialReason].
///
/// Carries no text. A consumer asks [isAllowed] and, when denied, hands the
/// reason to the host, which picks the feedback text from it.
@immutable
sealed class Capability {
  const Capability._();

  /// The action is allowed.
  const factory Capability.allowed() = Capability$Allowed;

  /// The action is denied for [reason].
  const factory Capability.denied(DenialReason reason) = Capability$Denied;

  /// Whether the action is allowed.
  bool get isAllowed;

  /// Why the action is denied; null when it is allowed.
  DenialReason? get reason;
}

/// [Capability.allowed].
final class Capability$Allowed extends Capability {
  /// An allowed action.
  const Capability$Allowed() : super._();

  @override
  bool get isAllowed => true;

  @override
  DenialReason? get reason => null;

  @override
  bool operator ==(Object other) => other is Capability$Allowed;

  @override
  int get hashCode => (Capability$Allowed).hashCode;

  @override
  String toString() => 'Capability.allowed';
}

/// [Capability.denied].
final class Capability$Denied extends Capability {
  /// A denied action.
  const Capability$Denied(this.reason) : super._();

  /// Why the action is denied.
  @override
  final DenialReason reason;

  @override
  bool get isAllowed => false;

  @override
  bool operator ==(Object other) =>
      other is Capability$Denied && other.reason == reason;

  @override
  int get hashCode => Object.hash(Capability$Denied, reason);

  @override
  String toString() => 'Capability.denied($reason)';
}

/// Why a [Capability] is denied; the host picks the feedback text from it.
///
/// The host resolves its backend's rights into one of the host forms
/// ([everyone], [restricted], [unlockable], [other]). The strings it puts in
/// ([DenialReason.unlockable], [DenialReason.other]) are host tags, never
/// user text: they reach diagnostics.
///
/// Two forms are the packages' own, raised where no host reason exists:
/// [noWriteAccess] (a write access that replaces the input row without a
/// restriction, asked for its panel's text) and [sendPending] (slow mode
/// holding a send while a message is still sending). They are types, not
/// tags, so a host's own `other` tag can never be read as one of them.
@immutable
sealed class DenialReason {
  const DenialReason._();

  /// Denied for every member of the chat.
  const factory DenialReason.everyone() = DenialReason$Everyone;

  /// Denied for this user, until [until], or for good when [until] is null.
  const factory DenialReason.restricted({DateTime? until}) =
      DenialReason$Restricted;

  /// Denied, and the user can lift it; [kind] is an opaque host string for
  /// what lifts it.
  const factory DenialReason.unlockable(String kind) = DenialReason$Unlockable;

  /// Any other host reason, by the host's [tag].
  const factory DenialReason.other(String tag) = DenialReason$Other;

  /// Raised by a package: the user may not write because [access] replaces
  /// the input row (read only, join, request to join, a host form).
  const factory DenialReason.noWriteAccess(WriteAccess access) =
      DenialReason$NoWriteAccess;

  /// Raised by a package: a message of the user's is still sending, which
  /// holds the next send in slow mode.
  const factory DenialReason.sendPending() = DenialReason$SendPending;

  /// The reason's form for diagnostics events: `everyone`, `restricted`,
  /// `restrictedUntil` (the date left out), `unlockable(kind)`,
  /// `other(tag)`, `noWriteAccess(form)` or `sendPending`.
  ///
  /// Always fits a field: a host string longer than a field holds is
  /// clipped, so the event that carries it never fails its own check.
  String get diagnosticForm;

  // `name(tag)`, the tag clipped so the whole fits a field.
  static String _tagged(String name, String tag) {
    final room = ChatEvent.maxStringFieldLength - name.length - 2;
    final shown = tag.length <= room ? tag : tag.substring(0, room);
    return '$name($shown)';
  }
}

/// [DenialReason.everyone].
final class DenialReason$Everyone extends DenialReason {
  /// Denied for every member.
  const DenialReason$Everyone() : super._();

  @override
  String get diagnosticForm => 'everyone';

  @override
  bool operator ==(Object other) => other is DenialReason$Everyone;

  @override
  int get hashCode => (DenialReason$Everyone).hashCode;

  @override
  String toString() => 'everyone';
}

/// [DenialReason.restricted].
final class DenialReason$Restricted extends DenialReason {
  /// Denied for this user.
  const DenialReason$Restricted({this.until}) : super._();

  /// When the restriction ends; null when it is for good.
  final DateTime? until;

  @override
  String get diagnosticForm => switch (until) {
    null => 'restricted',
    _ => 'restrictedUntil',
  };

  @override
  bool operator ==(Object other) =>
      other is DenialReason$Restricted && other.until == until;

  @override
  int get hashCode => Object.hash(DenialReason$Restricted, until);

  @override
  String toString() => switch (until) {
    final until? => 'restricted(until: ${until.toIso8601String()})',
    null => 'restricted',
  };
}

/// [DenialReason.unlockable].
final class DenialReason$Unlockable extends DenialReason {
  /// Denied, and the user can lift it.
  const DenialReason$Unlockable(this.kind) : super._();

  /// What lifts it, in the host's terms.
  final String kind;

  @override
  String get diagnosticForm => DenialReason._tagged('unlockable', kind);

  @override
  bool operator ==(Object other) =>
      other is DenialReason$Unlockable && other.kind == kind;

  @override
  int get hashCode => Object.hash(DenialReason$Unlockable, kind);

  @override
  String toString() => 'unlockable($kind)';
}

/// [DenialReason.other].
final class DenialReason$Other extends DenialReason {
  /// Another host reason.
  const DenialReason$Other(this.tag) : super._();

  /// The host's tag for the reason.
  final String tag;

  @override
  String get diagnosticForm => DenialReason._tagged('other', tag);

  @override
  bool operator ==(Object other) =>
      other is DenialReason$Other && other.tag == tag;

  @override
  int get hashCode => Object.hash(DenialReason$Other, tag);

  @override
  String toString() => 'other($tag)';
}

/// [DenialReason.noWriteAccess].
final class DenialReason$NoWriteAccess extends DenialReason {
  /// The user may not write because of [access].
  const DenialReason$NoWriteAccess(this.access) : super._();

  /// The write access that replaces the input row.
  final WriteAccess access;

  /// The form alone: a host form's tag stays out of the event.
  @override
  String get diagnosticForm => 'noWriteAccess(${access.diagnosticForm})';

  @override
  bool operator ==(Object other) =>
      other is DenialReason$NoWriteAccess && other.access == access;

  @override
  int get hashCode => Object.hash(DenialReason$NoWriteAccess, access);

  @override
  String toString() => 'noWriteAccess($access)';
}

/// [DenialReason.sendPending].
final class DenialReason$SendPending extends DenialReason {
  /// A message still sending holds the send.
  const DenialReason$SendPending() : super._();

  @override
  String get diagnosticForm => 'sendPending';

  @override
  bool operator ==(Object other) => other is DenialReason$SendPending;

  @override
  int get hashCode => (DenialReason$SendPending).hashCode;

  @override
  String toString() => 'sendPending';
}
