import 'package:chat_capabilities/src/flags/protection_flags.dart';
import 'package:meta/meta.dart';

/// The protection group of the chat capabilities: whether content may leave
/// the chat, for the chat as a whole.
///
/// The value knows no messages. A message's own protected flag lives in the
/// caller's model, and the caller adds it on top of these through
/// [forMessage].
@immutable
final class ChatProtection {
  /// Chat-level protection; the default protects nothing.
  const ChatProtection({
    bool copy = true,
    bool forward = true,
    bool save = true,
    bool captureBlocked = false,
  }) : _bits =
           // The bit order of `ProtectionFlags`, its serialised form. A
           // const constructor cannot call the flags' own constructor.
           (copy ? 0 : 1 << 0) |
           (forward ? 0 : 1 << 1) |
           (save ? 0 : 1 << 2) |
           (captureBlocked ? 1 << 3 : 0);

  /// Chat-level protection of [flags] (a set flag restricts).
  ChatProtection.of(ProtectionFlags flags) : _bits = flags.bits;

  // The one source of the value: what [flags] holds, which every getter
  // below reads.
  final int _bits;

  /// What the chat's protection denies, as flags (a set flag restricts).
  ProtectionFlags get flags => ProtectionFlags.fromBits(_bits);

  /// Whether messages may be copied (menus and text selection).
  bool get copy => !flags.contains(ProtectionFlags.copy);

  /// Whether messages may be forwarded.
  bool get forward => !flags.contains(ProtectionFlags.forward);

  /// Whether media may be saved to the device.
  bool get save => !flags.contains(ProtectionFlags.save);

  /// Whether screen capture is blocked while the chat shows; the host sets
  /// the platform's secure flag from it.
  bool get captureBlocked => flags.contains(ProtectionFlags.captureBlocked);

  /// What protection denies for one message: the chat's [flags], plus copy,
  /// forward and save when the message itself is protected
  /// ([messageProtected], which the caller reads from its own model).
  ///
  /// Screen capture is the chat's alone: a protected message does not block
  /// it.
  ProtectionFlags forMessage({required bool messageProtected}) =>
      messageProtected ? flags | _protectedMessage : flags;

  static final _protectedMessage =
      ProtectionFlags.copy | ProtectionFlags.forward | ProtectionFlags.save;

  /// A copy with the given fields replaced.
  ChatProtection copyWith({
    bool? copy,
    bool? forward,
    bool? save,
    bool? captureBlocked,
  }) => ChatProtection(
    copy: copy ?? this.copy,
    forward: forward ?? this.forward,
    save: save ?? this.save,
    captureBlocked: captureBlocked ?? this.captureBlocked,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatProtection && other._bits == _bits;

  @override
  int get hashCode => _bits.hashCode;

  @override
  String toString() =>
      'ChatProtection(copy: $copy, forward: $forward, save: $save, '
      'captureBlocked: $captureBlocked)';
}
