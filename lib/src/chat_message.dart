import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:meta/meta.dart';

@immutable
sealed class ChatMessage implements IChatMessage {
  const ChatMessage({
    required this.id,
    required this.updatedAt,
    required this.createdAt,
  });

  @override
  final int id;

  @override
  final DateTime createdAt;

  @override
  final DateTime updatedAt;
}

class ChatMessage$System extends ChatMessage {
  const ChatMessage$System({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required this.content,
  });

  /// The content of the system message.
  final String content;
}

class ChatMessage$User extends ChatMessage {
  const ChatMessage$User({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required this.content,
  });

  /// The content of the user message.
  final String content;
}
