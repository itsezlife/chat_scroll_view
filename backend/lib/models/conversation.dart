import 'dart:convert';

/// Wire-format conversation metadata from GET /api/conversation.
class ConversationDto {
  const ConversationDto({
    required this.title,
    required this.totalMessages,
    required this.chunkSize,
    required this.senders,
  });

  final String title;
  final int totalMessages;
  final int chunkSize;
  final List<String> senders;

  Map<String, Object?> toJson() => {
    'title': title,
    'totalMessages': totalMessages,
    'chunkSize': chunkSize,
    'senders': senders,
  };

  factory ConversationDto.fromRow(Map<String, Object?> row) {
    final sendersJson = row['senders_json']! as String;
    final senders =
        (jsonDecode(sendersJson) as List<Object?>).cast<String>();
    return ConversationDto(
      title: row['title']! as String,
      totalMessages: row['total_messages']! as int,
      chunkSize: row['chunk_size']! as int,
      senders: senders,
    );
  }
}
