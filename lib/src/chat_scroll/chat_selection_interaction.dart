import 'dart:ui' show Rect;

import 'package:content_model/content_model.dart'
    show ContentKey, ContentKey$Document;
import 'package:flutter/foundation.dart';

/// Host-observable outcome from the selection facade (Copy, link, code,
/// mention, hashtag, embed, sticker).
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

  /// A resolved mention (`[@name](mention:id)`) activated in a markdown body.
  /// Never a [ChatLinkActivated]: the engine paints and reports a mention as a
  /// style of its own.
  const factory ChatSelectionInteraction.resolvedMentionActivated({
    required int messageId,
    required String name,
    required String id,
    required ChatInlineGesture gesture,
  }) = ChatResolvedMentionActivated;

  /// A typed username (`[@name](username:name)`) activated in a markdown
  /// body. Not resolved to anyone, so it carries no id.
  const factory ChatSelectionInteraction.usernameMentionActivated({
    required int messageId,
    required String name,
    required ChatInlineGesture gesture,
  }) = ChatUsernameMentionActivated;

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

  /// The sticker of an emoji-only body tapped, or held. Always emitted for a
  /// tap: the body replays the animation on its own under its tap policy, and
  /// what else a tap means (an interaction effect, a pack sheet for a custom
  /// emoji) is the host's. See [ChatStickerActivated] for the payload.
  const factory ChatSelectionInteraction.stickerActivated({
    required int messageId,
    required ContentKey content,
    required ChatInlineGesture gesture,
    required Rect stickerRect,
    required Duration tapTime,
  }) = ChatStickerActivated;

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

/// A mention activated in a markdown body: a [ChatResolvedMentionActivated]
/// or a [ChatUsernameMentionActivated].
///
/// A host that treats both alike matches this type; one that opens a user for
/// a resolved mention matches the pair. Only the resolved variant has an id.
@immutable
sealed class ChatMentionActivated extends ChatSelectionInteraction {
  /// Base constructor for the mention variants.
  const ChatMentionActivated({
    required this.messageId,
    required this.name,
    required this.gesture,
  });

  /// Message whose body contains the mention.
  final int messageId;

  /// The label of a resolved mention, or the username.
  final String name;

  /// Tap vs long-press.
  final ChatInlineGesture gesture;
}

/// A resolved mention activated in a markdown body.
///
/// Construct via [ChatSelectionInteraction.resolvedMentionActivated].
@immutable
final class ChatResolvedMentionActivated extends ChatMentionActivated {
  /// Creates a resolved-mention activation interaction.
  const ChatResolvedMentionActivated({
    required super.messageId,
    required super.name,
    required this.id,
    required super.gesture,
  });

  /// The id of the user the sender's app resolved the mention to.
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatResolvedMentionActivated &&
          messageId == other.messageId &&
          id == other.id &&
          name == other.name &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, id, name, gesture);

  @override
  String toString() =>
      'ChatResolvedMentionActivated(messageId: $messageId, id: $id, '
      'name: $name, gesture: $gesture)';
}

/// A typed username activated in a markdown body.
///
/// Construct via [ChatSelectionInteraction.usernameMentionActivated].
@immutable
final class ChatUsernameMentionActivated extends ChatMentionActivated {
  /// Creates a username-mention activation interaction.
  const ChatUsernameMentionActivated({
    required super.messageId,
    required super.name,
    required super.gesture,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatUsernameMentionActivated &&
          messageId == other.messageId &&
          name == other.name &&
          gesture == other.gesture;

  @override
  int get hashCode => Object.hash(messageId, name, gesture);

  @override
  String toString() =>
      'ChatUsernameMentionActivated(messageId: $messageId, '
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

/// The sticker of an emoji-only body tapped, or held.
///
/// This is the one event a host needs to build a direct-tap interaction on:
/// a larger effect over the list, a haptic, a batch sent to the peer. It
/// carries everything the viewport knows and nothing it would have to decide:
/// which emoji ([content], [isCustomEmoji]), which message, where the sticker
/// is drawn ([stickerRect], global coordinates, read when the tap landed) and
/// when ([tapTime], monotonic). Whether the sticker also replayed is not part
/// of it; the host never has to wait for the body.
///
/// A tap is the interaction. A long press ([gesture]) carries no effect: it
/// opens the message menu or selects the message, and is told so the body can
/// follow its tap policy (`ChatStickerTapPolicy.replaysOn`). It is not told
/// while message selection suppresses inline activations.
///
/// Construct via [ChatSelectionInteraction.stickerActivated].
@immutable
final class ChatStickerActivated extends ChatSelectionInteraction {
  /// Creates a sticker-activation interaction.
  const ChatStickerActivated({
    required this.messageId,
    required this.content,
    required this.gesture,
    required this.stickerRect,
    required this.tapTime,
  });

  /// Message whose body shows the sticker.
  final int messageId;

  /// The emoji of the message: a unicode key as the sender wrote it (a host
  /// normalises it, skin tone and selector, before it looks an effect up), or
  /// a custom emoji's document.
  final ContentKey content;

  /// Whether [content] is a custom emoji.
  bool get isCustomEmoji => content is ContentKey$Document;

  /// Tap vs long-press.
  final ChatInlineGesture gesture;

  /// Where the sticker was drawn when the gesture landed, in global
  /// coordinates. A host converts it to its overlay's space, and reads
  /// `ChatSelectionController.stickerRectOf` for its place later, since the
  /// row scrolls.
  final Rect stickerRect;

  /// When the gesture was activated, on the facade's monotonic clock
  /// (`ChatSelectionController.monotonicClock`): only differences between two
  /// of these mean anything, like the offsets of a batch.
  final Duration tapTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatStickerActivated &&
          messageId == other.messageId &&
          content == other.content &&
          gesture == other.gesture &&
          stickerRect == other.stickerRect &&
          tapTime == other.tapTime;

  @override
  int get hashCode =>
      Object.hash(messageId, content, gesture, stickerRect, tapTime);

  @override
  String toString() =>
      'ChatStickerActivated(messageId: $messageId, content: $content, '
      'gesture: $gesture, stickerRect: $stickerRect, tapTime: $tapTime)';
}
