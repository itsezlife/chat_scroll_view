import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:meta/meta.dart';

/// Test double of the example app's sealed chat message.
///
/// Package tests must not depend on `example/`. This fixture implements
/// [IChatMessage] with the same leaf types the demo uses.
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

  /// The content of the user message.
  final String content;
}
