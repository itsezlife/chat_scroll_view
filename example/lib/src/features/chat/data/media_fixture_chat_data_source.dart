import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/media_fixture_messages.dart';

/// In-memory [ChatDataSource] seeded with media layout fixtures.
///
/// Owns: fixture upsert + send/edit/delete demos. Does not own the per-chat
/// [GroupedMessagesMap] — the chat surface constructs that and syncs from
/// loaded [UserChatMessage] rows.
final class MediaFixtureChatDataSource extends ChatDataSource {
  /// Upserts [buildMediaFixtureMessages] and seeds closed boundaries.
  MediaFixtureChatDataSource({DateTime? baseTime}) {
    final messages = buildMediaFixtureMessages(baseTime: baseTime);
    upsertMessages(messages);
    if (messages.isNotEmpty) {
      seedBoundaries(
        oldestKnownId: messages.first.id,
        newestKnownId: messages.last.id,
        reachedOldest: true,
        reachedNewest: true,
      );
    } else {
      seedBoundaries(reachedOldest: true, reachedNewest: true);
    }
  }

  final Map<int, IChatMessage> _tailOverrides = <int, IChatMessage>{};

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    final oldest = oldestKnownId;
    final newest = newestKnownId;
    if (oldest == null || newest == null) {
      return const [];
    }
    final lo = fromId.clamp(oldest, newest);
    final hi = toId.clamp(oldest, newest);
    final result = <IChatMessage>[];
    for (var id = lo; id <= hi; id++) {
      if (pendingRemovalIds.contains(id)) {
        continue;
      }
      if (getMessage(id) ?? _tailOverrides[id] case final message?) {
        result.add(message);
      }
    }
    return result;
  }

  /// Demo integrator: append a text message at the tail.
  UserChatMessage sendMessage({
    required String sender,
    required String content,
  }) {
    final id = nextInsertId;
    final now = DateTime.now();
    final message = UserChatMessage(
      id: id,
      sender: sender,
      createdAt: now,
      updatedAt: now,
      content: content,
    );
    _tailOverrides[id] = message;
    insertMessage(message, reason: 'demo-send');
    return message;
  }

  /// Demo integrator: edit text; preserves media fields on the updated row.
  void editMessage(UserChatMessage message, String newContent) {
    updateMessage(
      UserChatMessage(
        id: message.id,
        sender: message.sender,
        createdAt: message.createdAt,
        updatedAt: DateTime.now(),
        content: newContent,
        groupId: message.groupId,
        aspectRatio: message.aspectRatio,
        mediaKind: message.mediaKind,
        caption: message.caption,
        invertMedia: message.invertMedia,
      ),
      reason: 'demo-edit',
    );
  }

  @override
  void removeMessages(Iterable<int> ids, {Object? reason}) {
    ids.forEach(_tailOverrides.remove);
    super.removeMessages(ids, reason: reason ?? 'demo-delete');
  }
}
