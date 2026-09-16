import 'package:flutter/foundation.dart';

/// Host-observable outcome from the selection facade (Copy, link, code).
///
/// One sealed channel replaces parallel typed hooks so hosts switch once for
/// feedback UI and side effects. Message-menu entry
/// (`ChatScrollView.onIdleMessageTap` / `onSecondaryMessageTap`) stays on the
/// viewport — slot geometry, not selection interactions.
@immutable
sealed class ChatSelectionInteraction {
  /// Base constructor for interaction variants.
  const ChatSelectionInteraction();

  /// Successful clipboard Copy completed by the selection facade.
  const factory ChatSelectionInteraction.copied({
    required String text,
    required ChatCopyOrigin origin,
    int? messageId,
    ChatInlineGesture? gesture,
  }) = ChatCopied;

  /// Hyperlink activation in a markdown body.
  const factory ChatSelectionInteraction.linkActivated({
    required int messageId,
    required String title,
    required String url,
    required ChatInlineGesture gesture,
  }) = ChatLinkActivated;

  /// Code / monospace activation when the facade does **not** auto-copy.
  const factory ChatSelectionInteraction.codeActivated({
    required int messageId,
    required String code,
    required ChatInlineGesture gesture,
  }) = ChatCodeActivated;
}

/// Where a successful clipboard Copy originated.
enum ChatCopyOrigin {
  /// [ChatSelectionController.copyTextSelection] wrote the active range.
  textSelection,

  /// Host or future engine path copied from message-selection membership.
  messageSelection,

  /// Inline code / monospace / fenced COPY chrome with
  /// [ChatSelectionController.copyCodeOnClick].
  codeTap,
}

/// Pointer gesture that activated an inline body hit (link or code).
enum ChatInlineGesture {
  /// Primary tap.
  tap,

  /// Long-press (link preview, hold-to-copy, host haptics, etc.).
  longPress,
}

/// Successful clipboard Copy completed by the selection facade.
///
/// Prefer this variant alone for “Copied” feedback UI. When
/// [origin] is [ChatCopyOrigin.codeTap], [messageId] and [gesture] are
/// non-null and no separate [ChatCodeActivated] is emitted.
///
/// Construct via [ChatSelectionInteraction.copied].
@immutable
final class ChatCopied extends ChatSelectionInteraction {
  /// Creates a Copy-success interaction.
  const ChatCopied({
    required this.text,
    required this.origin,
    this.messageId,
    this.gesture,
  });

  /// Plain text written to the clipboard.
  final String text;

  /// Which engine / host path performed the write.
  final ChatCopyOrigin origin;

  /// Message that owned the code hit when [origin] is [ChatCopyOrigin.codeTap].
  final int? messageId;

  /// Tap vs long-press when [origin] is [ChatCopyOrigin.codeTap]; otherwise
  /// null (text / message selection Copy has no inline gesture).
  final ChatInlineGesture? gesture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatCopied &&
          text == other.text &&
          origin == other.origin &&
          messageId == other.messageId &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(text, origin, messageId, gesture);

  @override
  String toString() =>
      'ChatCopied(text: ${text.length} chars, origin: $origin, '
      'messageId: $messageId, gesture: $gesture)';
}

/// Hyperlink activation in a markdown body.
///
/// Construct via [ChatSelectionInteraction.linkActivated].
@immutable
final class ChatLinkActivated extends ChatSelectionInteraction {
  /// Creates a link-activation interaction.
  const ChatLinkActivated({
    required this.messageId,
    required this.title,
    required this.url,
    required this.gesture,
  });

  /// Message whose body contains the link.
  final int messageId;

  /// Display title (may equal [url]).
  final String title;

  /// Target URL.
  final String url;

  /// Tap vs long-press.
  final ChatInlineGesture gesture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatLinkActivated &&
          messageId == other.messageId &&
          title == other.title &&
          url == other.url &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, title, url, gesture);

  @override
  String toString() =>
      'ChatLinkActivated(messageId: $messageId, title: $title, url: $url, '
      'gesture: $gesture)';
}

/// Code / monospace activation when the facade does **not** auto-copy.
///
/// Emitted only when [ChatSelectionController.copyCodeOnClick] is `false`.
/// When auto-copy is on, hosts receive [ChatCopied] with
/// [ChatCopyOrigin.codeTap] (and [ChatCopied.gesture]) instead — never both.
///
/// Construct via [ChatSelectionInteraction.codeActivated].
@immutable
final class ChatCodeActivated extends ChatSelectionInteraction {
  /// Creates a code-activation interaction (host owns clipboard).
  const ChatCodeActivated({
    required this.messageId,
    required this.code,
    required this.gesture,
  });

  /// Message whose body contains the code.
  final int messageId;

  /// Code / monospace text that was activated.
  final String code;

  /// Tap vs long-press (e.g. haptics only on long-press).
  final ChatInlineGesture gesture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatCodeActivated &&
          messageId == other.messageId &&
          code == other.code &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, code, gesture);

  @override
  String toString() =>
      'ChatCodeActivated(messageId: $messageId, code: ${code.length} chars, '
      'gesture: $gesture)';
}
