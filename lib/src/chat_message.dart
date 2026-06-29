import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
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
class SystemChatMessage extends ChatMessage {
  /// Creates a system-authored row (join notices, channel events, …).
  const SystemChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required this.content,
  });

  /// The content of the system message.
  final String content;
}

/// A user-authored message. `sealed`-pattern leaf of [ChatMessage].
class UserChatMessage extends ChatMessage {
  /// Creates a user-authored row with [content] body text.
  const UserChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required this.content,
  });

  /// Parses a JSON object shaped like the comments asset chunks:
  /// `{id, sender, content, createdAt, updatedAt?}`.
  ///
  /// Missing or unparseable timestamps fall back to [DateTime.now] for
  /// `createdAt` and to `createdAt` for `updatedAt`.
  factory UserChatMessage.fromJson(Map<String, dynamic> json) {
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? createdAt;
    return UserChatMessage(
      id: json['id']! as int,
      sender: json['sender']! as String,
      createdAt: createdAt,
      updatedAt: updatedAt,
      content: json['content']! as String,
    );
  }

  /// The content of the user message.
  final String content;
}
