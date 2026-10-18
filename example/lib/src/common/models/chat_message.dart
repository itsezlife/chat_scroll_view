import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart' show EmojiOnly, EmojiOnlyText;
import 'package:content_model/markdown.dart' show RichTextMarkdown;
import 'package:meta/meta.dart';

/// Base type for messages rendered in a [ChatScrollView].
///
/// Sealed so callers can pattern-match on [UserChatMessage] vs
/// [SystemChatMessage] without a catch-all. Implements [IChatMessage] for the
/// scroll engine's id / timestamp contract.
@immutable
sealed class ChatMessage implements IChatMessage {
  /// Shared fields for every message leaf — [id], [sender], and timestamps.
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.updatedAt,
    required this.createdAt,
  });

  @override
  final int id;

  @override
  final String sender;

  @override
  final DateTime createdAt;

  @override
  final DateTime updatedAt;
}

/// A system-authored message — service notifications, join/leave notices,
/// channel events. `sealed`-pattern leaf of [ChatMessage].
///
/// Parses [content] into [body] at construction so markdown work stays off the
/// widget mount / recycle path.
class SystemChatMessage extends ChatMessage {
  /// Creates a system-authored row and parses [content] into [body] once.
  SystemChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required String content,
  }) : body = Markdown.fromString(content);

  /// Already-parsed [body] — host cache, isolate batch, or future entities bridge.
  const SystemChatMessage.preParsed({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required this.body,
  });

  /// Pre-parsed markdown AST for paint and selection registration.
  final Markdown body;

  /// Original markdown source (same as [Markdown.markdown]).
  String get content => body.markdown;
}

/// A user-authored message. `sealed`-pattern leaf of [ChatMessage].
///
/// Parses [content] into [body] at construction so markdown work stays off the
/// widget mount / recycle path, and classifies it as emoji-only
/// ([emojiOnly]) in the same place for the same reason: the viewport never
/// re-detects (`ChatEmojiBody`).
class UserChatMessage extends ChatMessage {
  /// Creates a user-authored row and parses [content] into [body] once.
  UserChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required String content,
    this.hasMedia = false,
  }) : body = Markdown.fromString(content),
       emojiOnly = _emojiOnlyOf(content);

  /// Already-parsed [body] — host cache, isolate batch, or future entities bridge.
  UserChatMessage.preParsed({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required this.body,
    this.hasMedia = false,
  }) : emojiOnly = _emojiOnlyOf(body.markdown);

  /// Pre-parsed markdown AST for paint and selection registration.
  final Markdown body;

  /// The emoji of [content] when it is nothing but emoji (`EmojiOnlyText.of`),
  /// else null. Only half of the host's decision to show the emoji-only body:
  /// [hasMedia] and the chat's settings are the rest (`LargeEmojiPolicy`).
  final EmojiOnly? emojiOnly;

  /// Whether the message carries media, a link preview included: a media
  /// message is never shown as the emoji-only body.
  final bool hasMedia;

  /// Original markdown source (same as [Markdown.markdown]).
  String get content => body.markdown;

  // A body that is emoji-only starts with whitespace, an emoji (non-ASCII, or
  // a keycap's digit, `#` or `*`) or the `!` of a custom emoji's image: the
  // rest (almost every message) is turned down before it is decoded.
  static EmojiOnly? _emojiOnlyOf(String content) {
    for (final unit in content.codeUnits) {
      final blank = unit == 0x20 || unit == 0x09 || unit == 0x0A;
      if (blank) continue;
      final possible =
          unit >= 0x80 ||
          unit == 0x21 ||
          unit == 0x23 ||
          unit == 0x2A ||
          (unit >= 0x30 && unit <= 0x39);
      return possible
          ? EmojiOnlyText.of(RichTextMarkdown.decode(content))
          : null;
    }
    return null;
  }
}

/// Extension methods for [IChatMessage].
extension ChatMessageExtension on IChatMessage {
  /// The content of the message.
  String? get text => switch (this) {
    UserChatMessage(:final content) => content,
    SystemChatMessage(:final content) => content,
    _ => null,
  };

  /// The emoji of the message when its text is nothing but emoji, else null.
  EmojiOnly? get emojiOnly => switch (this) {
    UserChatMessage(:final emojiOnly) => emojiOnly,
    _ => null,
  };

  /// Whether the message carries media (a link preview included).
  bool get hasMedia => switch (this) {
    UserChatMessage(:final hasMedia) => hasMedia,
    _ => false,
  };

  /// Pre-parsed markdown body when this is a [ChatMessage] leaf; otherwise null.
  Markdown? get markdownBody => switch (this) {
    UserChatMessage(:final body) => body,
    SystemChatMessage(:final body) => body,
    _ => null,
  };
}
