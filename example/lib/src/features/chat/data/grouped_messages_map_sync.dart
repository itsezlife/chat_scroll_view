import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:message_media/message_media.dart';

/// Feeds [GroupedMessagesMap] from host messages that carry a `groupId`.
///
/// Owns: reconciliation of map membership against a snapshot of loaded
/// [UserChatMessage]s. Does not own map lifecycle (host constructs / disposes)
/// or singles (no `groupId` — those stay off the map).
///
/// Call after load and whenever present media rows change. Message IDs that
/// leave the snapshot are [GroupedMessagesMap.remove]d; others are
/// [GroupedMessagesMap.put] with current aspect / caption flags.
final class GroupedMessagesMapSync {
  /// Creates a sync helper bound to [map].
  GroupedMessagesMapSync(this.map);

  /// Per-chat map owned by the chat surface.
  final GroupedMessagesMap map;

  final Set<int> _syncedIds = {};

  /// Message IDs currently mirrored into [map] (observability / tests).
  Set<int> get syncedIds => Set.unmodifiable(_syncedIds);

  /// Reconciles [map] with [messages] that have both [UserChatMessage.groupId]
  /// and [UserChatMessage.aspectRatio].
  ///
  /// Text-only and single-media rows (no group id) are ignored. After this
  /// returns, [syncedIds] equals the set of album member ids in [messages].
  void sync(Iterable<IChatMessage> messages) {
    if (map.isDisposed) {
      _syncedIds.clear();
      return;
    }

    final next = <int>{};
    for (final message in messages) {
      if (message case UserChatMessage(
        :final id,
        :final groupId?,
        :final aspectRatio?,
        :final mediaKind,
        :final caption,
        :final invertMedia,
      )) {
        next.add(id);
        final hasCaption = switch (caption) {
          final text? when text.isNotEmpty => true,
          _ => false,
        };
        map.put(
          groupId: groupId,
          member: GroupedMapMember(
            messageId: id,
            aspectRatio: aspectRatio,
            kind: mediaKind ?? MediaKind.photo,
            hasCaption: hasCaption,
            invertMedia: invertMedia,
            captionText: caption,
          ),
        );
      }
    }

    _syncedIds.difference(next).forEach(map.remove);
    _syncedIds
      ..clear()
      ..addAll(next);
  }

  /// Clears host tracking after [GroupedMessagesMap.dispose] (or before).
  void reset() => _syncedIds.clear();
}
