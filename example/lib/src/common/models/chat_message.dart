import 'package:chat_scroll_view/chat_scroll_view.dart';
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
/// widget mount / recycle path.
class UserChatMessage extends ChatMessage {
  /// Creates a user-authored row and parses [content] into [body] once.
  UserChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required String content,
  }) : body = Markdown.fromString(content);

  /// Already-parsed [body] — host cache, isolate batch, or future entities bridge.
  const UserChatMessage.preParsed({
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

/// Extension methods for [IChatMessage].
extension ChatMessageExtension on IChatMessage {
  /// The content of the message.
  String? get text => switch (this) {
    UserChatMessage(:final content) => content,
    SystemChatMessage(:final content) => content,
    _ => null,
  };

  /// Pre-parsed markdown body when this is a [ChatMessage] leaf; otherwise null.
  Markdown? get markdownBody => switch (this) {
    UserChatMessage(:final body) => body,
    SystemChatMessage(:final body) => body,
    _ => null,
  };
}
