import 'package:chat_demo_backend/models/conversation.dart';
import 'package:chat_demo_backend/models/message.dart';
import 'package:chat_demo_backend/models/range_meta.dart';
import 'package:chat_demo_backend/storage/database.dart';

/// Message and conversation persistence.
class MessageRepository {
  MessageRepository(this._database);

  final DemoDatabase _database;

  bool get isSeeded {
    final count = _database.messageCount();
    if (count == 0) return false;
    final meta = getConversation();
    return meta != null;
  }

  ConversationDto? getConversation() {
    final rows = _database.raw.select(
      "SELECT title, total_messages, chunk_size, senders_json "
      "FROM conversation_meta WHERE id = 'default'",
    );
    if (rows.isEmpty) return null;
    return ConversationDto.fromRow(rows.first);
  }

  /// Fetch messages in inclusive [fromId, toId], ordered ascending.
  ({List<MessageDto> messages, RangeMeta rangeMeta}) fetchRange({
    required int fromId,
    required int toId,
  }) {
    final meta = getConversation();
    final total = meta?.totalMessages ?? 0;
    final rangeMeta = RangeMeta.compute(
      fromId: fromId,
      toId: toId,
      totalMessages: total,
    );

    if (total <= 0 || fromId >= total) {
      return (messages: const [], rangeMeta: rangeMeta);
    }

    final clampedTo = toId.clamp(0, total - 1);
    final rows = _database.raw.select(
      'SELECT id, sender, content, created_at FROM messages '
      'WHERE id >= ? AND id <= ? ORDER BY id ASC',
      [fromId, clampedTo],
    );

    final messages = [for (final row in rows) MessageDto.fromRow(row)];
    return (messages: messages, rangeMeta: rangeMeta);
  }
}
