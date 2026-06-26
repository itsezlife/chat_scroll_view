/// Wire-format message returned by GET /api/messages.
class MessageDto {
  const MessageDto({
    required this.id,
    required this.sender,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final String sender;
  final String content;
  final String createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'sender': sender,
    'content': content,
    'createdAt': createdAt,
  };

  factory MessageDto.fromRow(Map<String, Object?> row) => MessageDto(
    id: row['id']! as int,
    sender: row['sender']! as String,
    content: row['content']! as String,
    createdAt: row['created_at']! as String,
  );
}
