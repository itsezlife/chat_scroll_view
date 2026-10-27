import 'dart:ui' show Offset, Path, Rect;

import 'package:content_model/content_model.dart' show ContentKey;
import 'package:flutter/foundation.dart';

/// Semantic inline hit on a message body element: a hyperlink, a code block,
/// one of the three things the markdown engine paints as a style of its own
/// (an embed, a mention, a hashtag), or the sticker of an emoji-only body.
///
/// A hit is read from the span's style bits, never from its URL: a mention is
/// not a link and an image is not a link. A span inside a hidden spoiler is no
/// hit at all; the tap reveals it (see `ChatSelectionController.spoilers`).
///
/// Inline hits participate in viewport gesture arbitration: they are
/// first-class interactions that are not consumed solely as idle selection
/// dismissals or row toggles.
///
/// When produced by pointer hit-testing against mounted markdown surfaces,
/// carries the optional [contourPath] (closed vector-smoothed contour computed
/// by `ChatSmoothContour`) and [touchOrigin] (content-local coordinates of the
/// tap event) to drive tactile tap highlight animations.
@immutable
sealed class ChatInlineHit {
  /// Base constructor for inline hit variants.
  const ChatInlineHit();

  /// Creates a link hit.
  const factory ChatInlineHit.link({
    required int messageId,
    required String title,
    required String url,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Link;

  /// Creates a code or monospace snippet hit.
  const factory ChatInlineHit.code({
    required int messageId,
    required String code,
    String? language,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Code;

  /// Creates a hit on an inline embed: an image `![alt](scheme:id)` the body
  /// paints in the text.
  ///
  /// The host decides what an embed tap means; the viewport only reports it
  /// (and shows the click cursor when `ChatSelectionController.handlesEmbedHits`).
  const factory ChatInlineHit.embed({
    required int messageId,
    required String target,
    required String alt,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Embed;

  /// Creates a hit on a resolved mention, `[@name](mention:id)`: a user the
  /// sender's app resolved, carrying the user's [id].
  const factory ChatInlineHit.resolvedMention({
    required int messageId,
    required String name,
    required String id,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Mention$Resolved;

  /// Creates a hit on a typed username, `[@name](username:name)`: a name that
  /// was not resolved to anyone, so it carries no id.
  const factory ChatInlineHit.usernameMention({
    required int messageId,
    required String name,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Mention$Username;

  /// Creates a hit on a hashtag: `[#tag](hashtag:tag)`.
  const factory ChatInlineHit.hashtag({
    required int messageId,
    required String tag,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Hashtag;

  /// Creates a hit on the sticker of an emoji-only body: the lone emoji of the
  /// message, shown large (`ChatEmojiBody`).
  ///
  /// [content] is the emoji the sender wrote: a `ContentKey.unicode` for an
  /// emoji with an animated sticker, a `ContentKey.document` for a custom
  /// emoji. [stickerRect] is where the sticker is drawn, in global
  /// coordinates, when the hit was read. The body replays the animation
  /// itself; what else a tap means (a pack sheet, an effect) is the host's.
  const factory ChatInlineHit.sticker({
    required int messageId,
    required ContentKey content,
    required Rect stickerRect,
  }) = ChatInlineHit$Sticker;

  /// The message ID whose body contains the hit element.
  abstract final int messageId;

  /// Optional vector-smoothed contour path wrapping the hit span's line bounding boxes.
  Path? get contourPath;

  /// Optional content-local coordinates of the pointer origin where the tap occurred.
  Offset? get touchOrigin;
}

/// An inline link hit in a markdown message body.
///
/// Carries the tapped hyperlink's target [url] and display [title], alongside
/// optional geometry for tactile tap feedback.
@immutable
final class ChatInlineHit$Link extends ChatInlineHit {
  /// Creates a link hit descriptor.
  const ChatInlineHit$Link({
    required this.messageId,
    required this.title,
    required this.url,
    this.contourPath,
    this.touchOrigin,
  });

  @override
  final int messageId;

  /// Display text or label of the link (falls back to [url] if none).
  final String title;

  /// Target URL string parsed from markdown.
  final String url;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Link &&
          other.messageId == messageId &&
          other.title == title &&
          other.url == url &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode => Object.hash(messageId, title, url, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Link(messageId: '
      '$messageId, title: $title, url: $url, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// An inline code hit in a markdown message body.
///
/// Produced by taps on fenced code blocks or inline monospace code snippets,
/// alongside optional geometry for tactile tap feedback.
@immutable
final class ChatInlineHit$Code extends ChatInlineHit {
  /// Creates a code hit descriptor.
  const ChatInlineHit$Code({
    required this.messageId,
    required this.code,
    this.language,
    this.contourPath,
    this.touchOrigin,
  });

  @override
  final int messageId;

  /// Text content of the code block or monospace span.
  final String code;

  /// Programming language identifier if present on a fenced code block,
  /// or null for inline monospace spans or unspecified blocks.
  final String? language;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Code &&
          other.messageId == messageId &&
          other.code == code &&
          other.language == language &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode => Object.hash(messageId, code, language, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Code(messageId: '
      '$messageId, code: $code, language: $language, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// An inline embed hit in a markdown message body.
///
/// Carries the embed's [target] as the markup spells it (`unicode:1F44D`,
/// `document:5368`) and its [alt] text, with optional geometry for tactile
/// tap feedback.
@immutable
final class ChatInlineHit$Embed extends ChatInlineHit {
  /// Creates an embed hit descriptor.
  const ChatInlineHit$Embed({
    required this.messageId,
    required this.target,
    required this.alt,
    this.contourPath,
    this.touchOrigin,
  });

  @override
  final int messageId;

  /// The destination of the image: `scheme:id`.
  final String target;

  /// The alternative text of the embed: what copy, selection and screen
  /// readers use in its place.
  final String alt;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Embed &&
          other.messageId == messageId &&
          other.target == target &&
          other.alt == alt &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode => Object.hash(messageId, target, alt, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Embed(messageId: '
      '$messageId, target: $target, alt: $alt, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// An inline mention hit in a markdown message body: either a
/// [ChatInlineHit$Mention$Resolved] or a [ChatInlineHit$Mention$Username].
///
/// The two spellings are separate variants because only one of them has an
/// id: a switch over the pair is exhaustive and the id of a resolved mention
/// is never null.
@immutable
sealed class ChatInlineHit$Mention extends ChatInlineHit {
  /// Base constructor for the mention variants.
  const ChatInlineHit$Mention({required this.messageId, required this.name, this.contourPath, this.touchOrigin});

  @override
  final int messageId;

  /// The label of a resolved mention as the text shows it (`@Ann`); the
  /// username of a typed one.
  final String name;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;
}

/// A hit on a resolved mention, `[@name](mention:id)`.
@immutable
final class ChatInlineHit$Mention$Resolved extends ChatInlineHit$Mention {
  /// Creates a resolved-mention hit descriptor.
  const ChatInlineHit$Mention$Resolved({
    required super.messageId,
    required super.name,
    required this.id,
    super.contourPath,
    super.touchOrigin,
  });

  /// The id of the user the sender's app resolved the mention to.
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Mention$Resolved &&
          other.messageId == messageId &&
          other.id == id &&
          other.name == name &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode => Object.hash(messageId, id, name, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Mention$Resolved(messageId: '
      '$messageId, id: $id, name: $name, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// A hit on a typed username, `[@name](username:name)`: not resolved to
/// anyone, so it carries only the name.
@immutable
final class ChatInlineHit$Mention$Username extends ChatInlineHit$Mention {
  /// Creates a username-mention hit descriptor.
  const ChatInlineHit$Mention$Username({
    required super.messageId,
    required super.name,
    super.contourPath,
    super.touchOrigin,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Mention$Username &&
          other.messageId == messageId &&
          other.name == name &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode => Object.hash(messageId, name, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Mention$Username(messageId: '
      '$messageId, name: $name, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// An inline hashtag hit in a markdown message body.
@immutable
final class ChatInlineHit$Hashtag extends ChatInlineHit {
  /// Creates a hashtag hit descriptor.
  const ChatInlineHit$Hashtag({required this.messageId, required this.tag, this.contourPath, this.touchOrigin});

  @override
  final int messageId;

  /// The tag, without the `#`.
  final String tag;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Hashtag &&
          other.messageId == messageId &&
          other.tag == tag &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode => Object.hash(messageId, tag, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Hashtag(messageId: '
      '$messageId, tag: $tag, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// A hit on the sticker of an emoji-only body.
///
/// It has no text contour: the sticker is an image, so a tap gives no
/// highlight of the kind a link does.
@immutable
final class ChatInlineHit$Sticker extends ChatInlineHit {
  /// Creates a sticker hit descriptor.
  const ChatInlineHit$Sticker({required this.messageId, required this.content, required this.stickerRect});

  @override
  final int messageId;

  /// The emoji of the message.
  final ContentKey content;

  /// Where the sticker is drawn, in global coordinates: the rectangle an
  /// effect over it is anchored to.
  final Rect stickerRect;

  @override
  Path? get contourPath => null;

  @override
  Offset? get touchOrigin => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Sticker &&
          other.messageId == messageId &&
          other.content == content &&
          other.stickerRect == stickerRect;

  @override
  int get hashCode => Object.hash(messageId, content, stickerRect);

  @override
  String toString() =>
      r'ChatInlineHit$Sticker(messageId: '
      '$messageId, content: $content, stickerRect: $stickerRect)';
}
