import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart'
    show ChatMentionKind;
import 'package:flutter/foundation.dart';

/// Host-observable outcome from the selection facade (Copy, link, code,
/// mention, hashtag, embed).
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

  /// A mention (`[@name](mention:id)` or `[@name](username:name)`) activated in
  /// a markdown body. Never a [ChatLinkActivated]: the engine paints and
  /// reports a mention as a style of its own.
  const factory ChatSelectionInteraction.mentionActivated({
    required int messageId,
    required ChatMentionKind kind,
    required String name,
    required ChatInlineGesture gesture,
    String? id,
  }) = ChatMentionActivated;

  /// A hashtag (`[#tag](hashtag:tag)`) activated in a markdown body.
  const factory ChatSelectionInteraction.hashtagActivated({
    required int messageId,
    required String tag,
    required ChatInlineGesture gesture,
  }) = ChatHashtagActivated;

  /// An inline embed activated in a markdown body. Emitted only when the host
  /// opted in with `ChatSelectionController.handlesEmbedHits`.
  const factory ChatSelectionInteraction.embedActivated({
    required int messageId,
    required String target,
    required String alt,
    required ChatInlineGesture gesture,
  }) = ChatEmbedActivated;

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

/// Pointer gesture that activated an inline body hit (link, mention, hashtag,
/// embed or code).
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

/// A mention activated in a markdown body.
///
/// Construct via [ChatSelectionInteraction.mentionActivated].
@immutable
final class ChatMentionActivated extends ChatSelectionInteraction {
  /// Creates a mention-activation interaction.
  const ChatMentionActivated({
    required this.messageId,
    required this.kind,
    required this.name,
    required this.gesture,
    this.id,
  });

  /// Message whose body contains the mention.
  final int messageId;

  /// A resolved user or a typed username.
  final ChatMentionKind kind;

  /// The user id of a [ChatMentionKind.resolved] mention; null for a username.
  final String? id;

  /// The label of a resolved mention, or the username.
  final String name;

  /// Tap vs long-press.
  final ChatInlineGesture gesture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMentionActivated &&
          messageId == other.messageId &&
          kind == other.kind &&
          id == other.id &&
          name == other.name &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, kind, id, name, gesture);

  @override
  String toString() =>
      'ChatMentionActivated(messageId: $messageId, kind: $kind, id: $id, '
      'name: $name, gesture: $gesture)';
}

/// A hashtag activated in a markdown body.
///
/// Construct via [ChatSelectionInteraction.hashtagActivated].
@immutable
final class ChatHashtagActivated extends ChatSelectionInteraction {
  /// Creates a hashtag-activation interaction.
  const ChatHashtagActivated({
    required this.messageId,
    required this.tag,
    required this.gesture,
  });

  /// Message whose body contains the hashtag.
  final int messageId;

  /// The tag, without the `#`.
  final String tag;

  /// Tap vs long-press.
  final ChatInlineGesture gesture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatHashtagActivated &&
          messageId == other.messageId &&
          tag == other.tag &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, tag, gesture);

  @override
  String toString() =>
      'ChatHashtagActivated(messageId: $messageId, tag: $tag, '
      'gesture: $gesture)';
}

/// An inline embed activated in a markdown body.
///
/// Construct via [ChatSelectionInteraction.embedActivated].
@immutable
final class ChatEmbedActivated extends ChatSelectionInteraction {
  /// Creates an embed-activation interaction.
  const ChatEmbedActivated({
    required this.messageId,
    required this.target,
    required this.alt,
    required this.gesture,
  });

  /// Message whose body contains the embed.
  final int messageId;

  /// The destination of the embed as the markup spells it: `scheme:id`.
  final String target;

  /// The embed's alternative text.
  final String alt;

  /// Tap vs long-press.
  final ChatInlineGesture gesture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatEmbedActivated &&
          messageId == other.messageId &&
          target == other.target &&
          alt == other.alt &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, target, alt, gesture);

  @override
  String toString() =>
      'ChatEmbedActivated(messageId: $messageId, target: $target, '
      'alt: $alt, gesture: $gesture)';
}
