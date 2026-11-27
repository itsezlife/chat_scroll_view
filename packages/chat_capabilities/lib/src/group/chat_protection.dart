import 'package:meta/meta.dart';

/// The protection group of the chat capabilities: whether content may leave
/// the chat, for the chat as a whole.
///
/// The value knows no messages. A message's own protected flag lives in the
/// caller's model, and the caller adds it on top of these.
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
