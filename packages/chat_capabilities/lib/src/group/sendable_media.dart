import 'dart:collection';

import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/flags/media_kind.dart';
import 'package:meta/meta.dart';

/// The media kinds the user may send, and why each other kind is denied:
/// `sending.media` of the chat capabilities.
///
/// The kinds are bits with no payload ([allowed]); the reasons live beside
/// them in [denials], keyed by kind. A kind outside [allowed] with no entry
/// reads as denied for everyone. An entry for an allowed kind breaks
/// `CapabilitiesRule.mediaDenialForAllowedKind`.
@immutable
final class SendableMedia {
  /// Sendable media; the default allows every kind.
  ///
  /// [denials] is held as given and read through an unmodifiable view; the
  /// host does not change the map afterwards ([copyWith] copies it).
  const SendableMedia({
    this.allowed = MediaKindSet.all,
    Map<MediaKind, DenialReason> denials = const {},
  }) : _denials = denials;

  /// The kinds the user may send.
  final MediaKindSet allowed;

  /// The reason of each kind not in [allowed].
  Map<MediaKind, DenialReason> get denials => UnmodifiableMapView(_denials);
  final Map<MediaKind, DenialReason> _denials;

  /// Why [kind] is denied, or null when it is allowed.
  ///
  /// A denied kind the host gave no reason for reads as
  /// [DenialReason.everyone]: the bit alone says only that nobody here may
  /// send it.
  DenialReason? reasonFor(MediaKind kind) {
    if (allowed.contains(kind)) return null;
    return _denials[kind] ?? const DenialReason.everyone();
  }

  /// The [denials] keys that name an allowed kind, which a valid value has
  /// none of.
  Iterable<MediaKind> get deniedButAllowed =>
      _denials.keys.where(allowed.contains);

  /// A copy with the given fields replaced.
  SendableMedia copyWith({
    MediaKindSet? allowed,
    Map<MediaKind, DenialReason>? denials,
  }) => SendableMedia(
    allowed: allowed ?? this.allowed,
    denials: switch (denials) {
      final denials? => Map.unmodifiable(denials),
      null => _denials,
    },
  );

  @override
  bool operator ==(Object other) {
    if (other is! SendableMedia || other.allowed != allowed) return false;
    if (identical(other._denials, _denials)) return true;
    if (other._denials.length != _denials.length) return false;
    for (final MapEntry(:key, :value) in _denials.entries) {
      // Values are never null, so a missing key reads as unequal too.
      if (other._denials[key] != value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    allowed,
    Object.hashAllUnordered(
      _denials.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'SendableMedia(allowed: ${allowed.kinds.map((k) => k.name)}, '
      'denials: $_denials)';
}
