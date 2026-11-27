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
}

/// [Capability.allowed].
final class Capability$Allowed extends Capability {
  /// An allowed action.
  const Capability$Allowed() : super._();

  @override
  bool get isAllowed => true;

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
/// The host resolves its backend's rights into one of these forms. The
/// strings it puts in ([DenialReason.unlockable], [DenialReason.other]) are
/// host tags, never user text: they reach diagnostics.
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
}

/// [DenialReason.everyone].
final class DenialReason$Everyone extends DenialReason {
  /// Denied for every member.
  const DenialReason$Everyone() : super._();

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
  bool operator ==(Object other) =>
      other is DenialReason$Other && other.tag == tag;

  @override
  int get hashCode => Object.hash(DenialReason$Other, tag);

  @override
  String toString() => 'other($tag)';
}
