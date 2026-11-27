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
    this.copy = true,
    this.forward = true,
    this.save = true,
    this.captureBlocked = false,
  });

  /// Whether messages may be copied (menus and text selection).
  final bool copy;

  /// Whether messages may be forwarded.
  final bool forward;

  /// Whether media may be saved to the device.
  final bool save;

  /// Whether screen capture is blocked while the chat shows; the host sets
  /// the platform's secure flag from it.
  final bool captureBlocked;

  /// What the chat's protection denies, as flags (a set flag restricts).
  ProtectionFlags get flags => ProtectionFlags.fromBits(
    (copy ? 0 : ProtectionFlags.copy.bits) |
        (forward ? 0 : ProtectionFlags.forward.bits) |
        (save ? 0 : ProtectionFlags.save.bits) |
        (captureBlocked ? ProtectionFlags.captureBlocked.bits : 0),
  );

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
      other is ChatProtection &&
      other.copy == copy &&
      other.forward == forward &&
      other.save == save &&
      other.captureBlocked == captureBlocked;

  @override
  int get hashCode => Object.hash(copy, forward, save, captureBlocked);

  @override
  String toString() =>
      'ChatProtection(copy: $copy, forward: $forward, save: $save, '
      'captureBlocked: $captureBlocked)';
}
