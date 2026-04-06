import 'package:meta/meta.dart';

@immutable
sealed class MessageEntity {
  const MessageEntity({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MessageEntity$System extends MessageEntity {
  const MessageEntity$System({
    required super.id,
    required super.content,
    required super.createdAt,
    required super.updatedAt,
  });
}

class MessageEntity$User extends MessageEntity {
  const MessageEntity$User({
    required super.id,
    required super.content,
    required super.createdAt,
    required super.updatedAt,
  });
}
