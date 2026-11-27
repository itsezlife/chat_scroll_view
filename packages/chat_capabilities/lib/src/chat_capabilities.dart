import 'dart:collection';

import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/group/chat_limits.dart';
import 'package:chat_capabilities/src/group/chat_protection.dart';
import 'package:chat_capabilities/src/group/sending_capabilities.dart';
import 'package:chat_capabilities/src/group/slow_mode.dart';
import 'package:chat_capabilities/src/group/write_access.dart';
import 'package:meta/meta.dart';

/// What the user may do in one chat: an outcome for each action, group by
/// group, and why when denied.
///
/// The host resolves its backend's rights into this value; it carries
/// outcomes and reasons, never protocol flags. Every group defaults to
/// allowing everything, so `const ChatCapabilities()` is what a
/// consumer assumes when the host provides no value.
///
/// A later group (reactions, commands, ...) arrives as a new field with an
/// allowed default; no field is removed or repurposed. A host rule the
/// packages do not model goes in [custom] under a host key.
///
/// Consumers take a `ValueListenable<ChatCapabilities>` and read their group
/// through `select`, which notifies only when that group changes.
@immutable
final class ChatCapabilities {
  /// The capabilities of a chat; each omitted group allows everything.
  ///
  /// [custom] is held as given and read through an unmodifiable view; the
  /// host does not change the map afterwards ([copyWith] copies it).
  const ChatCapabilities({
    this.sending = const SendingCapabilities(),
    this.writeAccess = const WriteAccess.canWrite(),
    this.slowMode = SlowMode.none,
    this.protection = const ChatProtection(),
    this.limits = const ChatLimits(),
    Map<String, Capability> custom = const {},
  }) : _custom = custom;

  /// What the user may send.
  final SendingCapabilities sending;

  /// Whether the user may write, or what replaces the input row.
  final WriteAccess writeAccess;

  /// One send unit per interval, when set.
  final SlowMode slowMode;

  /// Whether content may leave the chat.
  final ChatProtection protection;

  /// Message, caption, file and album limits.
  final ChatLimits limits;

  /// Host rules the packages do not model, by host key.
  Map<String, Capability> get custom => UnmodifiableMapView(_custom);
  final Map<String, Capability> _custom;

  /// A copy with the given groups replaced.
  ChatCapabilities copyWith({
    SendingCapabilities? sending,
    WriteAccess? writeAccess,
    SlowMode? slowMode,
    ChatProtection? protection,
    ChatLimits? limits,
    Map<String, Capability>? custom,
  }) => ChatCapabilities(
    sending: sending ?? this.sending,
    writeAccess: writeAccess ?? this.writeAccess,
    slowMode: slowMode ?? this.slowMode,
    protection: protection ?? this.protection,
    limits: limits ?? this.limits,
    custom: switch (custom) {
      final custom? => Map.unmodifiable(custom),
      null => _custom,
    },
  );

  /// The rules this value breaks, in group order; empty for a valid value.
  ///
  /// A value cannot check itself when it is built (it is const), so the
  /// listenable from `withDiagnostics` checks each value it passes on.
  List<CapabilitiesRule> get brokenRules => [
    if (sending.media.deniedButAllowed.isNotEmpty)
      CapabilitiesRule.mediaDenialForAllowedKind,
    if (slowMode case SlowMode$Active(
      :final interval,
    ) when interval <= Duration.zero)
      CapabilitiesRule.slowModeIntervalNotPositive,
    if (limits.messageLength < 1) CapabilitiesRule.messageLengthBelowOne,
    if (limits.captionLength < 0) CapabilitiesRule.captionLengthNegative,
    if (limits.fileSize case final size? when size < 1)
      CapabilitiesRule.fileSizeBelowOne,
    if (limits.albumSize < 1) CapabilitiesRule.albumSizeBelowOne,
    if (_custom.containsKey('')) CapabilitiesRule.customKeyEmpty,
  ];

  /// A short structured description of the value, for logs and debug
  /// screens: each group's outcomes, denials by reason form, the allowed
  /// media kinds and the protection flags with their bits, the slow mode
  /// state, the limits and the [custom] keys.
  ///
  /// Holds no user content: the only strings from the host are its tags
  /// (`unlockable` kinds, `other` and `custom` tags, [custom] keys).
  Map<String, Object> debugDescribe() => {
    'sending': {
      'text': _describe(sending.text),
      'media': {
        'allowed': [for (final kind in sending.media.allowed.kinds) kind.name],
        'bits': sending.media.allowed.bits,
        'denials': <String, Object>{
          for (final MapEntry(:key, :value) in sending.media.denials.entries)
            key.name: '$value',
        },
      },
      'stickers': _describe(sending.stickers),
      'linkPreviews': _describe(sending.linkPreviews),
      'polls': _describe(sending.polls),
      'inline': _describe(sending.inline),
    },
    'writeAccess': '$writeAccess',
    'slowMode': switch (slowMode) {
      SlowMode$None() => 'none',
      SlowMode$Active(:final interval, :final nextSendAt, :final pending) =>
        <String, Object>{
          'intervalMs': interval.inMilliseconds,
          'nextSendAt': ?nextSendAt?.toIso8601String(),
          'pending': pending,
        },
    },
    'protection': {
      'copy': protection.copy,
      'forward': protection.forward,
      'save': protection.save,
      'captureBlocked': protection.captureBlocked,
      'bits': protection.flags.bits,
    },
    'limits': {
      'messageLength': limits.messageLength,
      'captionLength': limits.captionLength,
      'fileSize': limits.fileSize ?? 'unlimited',
      'albumSize': limits.albumSize,
    },
    'custom': <String, Object>{
      for (final MapEntry(:key, :value) in _custom.entries)
        key: _describe(value),
    },
  };

  static String _describe(Capability capability) => switch (capability) {
    Capability$Allowed() => 'allowed',
    Capability$Denied(:final reason) => 'denied($reason)',
  };

  @override
  bool operator ==(Object other) =>
      other is ChatCapabilities &&
      other.sending == sending &&
      other.writeAccess == writeAccess &&
      other.slowMode == slowMode &&
      other.protection == protection &&
      other.limits == limits &&
      sameCustom(other._custom, _custom);

  /// Whether [a] and [b] hold the same custom capabilities, for a consumer
  /// that compares the [custom] groups of two values without building new
  /// ones.
  @internal
  static bool sameCustom(Map<String, Capability> a, Map<String, Capability> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      // Values are never null, so a missing key reads as unequal too.
      if (b[key] != value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    sending,
    writeAccess,
    slowMode,
    protection,
    limits,
    Object.hashAllUnordered(
      _custom.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'ChatCapabilities(sending: $sending, writeAccess: $writeAccess, '
      'slowMode: $slowMode, protection: $protection, limits: $limits, '
      'custom: $_custom)';
}

/// A rule a [ChatCapabilities] value can break, named by
/// [ChatCapabilities.brokenRules] and in the `invalidValue` diagnostics
/// event.
///
/// A rule's name is stable: logs filter by it.
enum CapabilitiesRule {
  /// `sending.media.denials` gives a reason for a kind that is allowed.
  mediaDenialForAllowedKind,

  /// An active slow mode's interval is zero or negative.
  slowModeIntervalNotPositive,

  /// The message length limit is below one code point.
  messageLengthBelowOne,

  /// The caption length limit is negative.
  captionLengthNegative,

  /// The file size limit is below one byte.
  fileSizeBelowOne,

  /// The album size limit is below one item.
  albumSizeBelowOne,

  /// A custom capability has an empty key.
  customKeyEmpty,
}
