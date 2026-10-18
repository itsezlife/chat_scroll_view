import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatStickerPlayLedger;

/// Which animated stickers a chat screen has already played, per message.
///
/// A lone unicode emoji plays its animation once, the first time the screen
/// shows it, and then rests on a frame; a tap plays it again. The body records the play
/// here when the animation is playing and asks here when it mounts, so a row
/// that is recycled and mounted again rests instead of playing again. The
/// memory is the chat screen's, not the asset cache's: the cache is shared by
/// every screen and keeps no per-chat history (ADR 029, per-chat controllers).
/// A new screen has a new memory, so a chat reopened later plays its stickers
/// again, as in the reference clients. It is not persisted.
final class StickerPlayMemory implements ChatStickerPlayLedger {
  final Set<int> _played = <int>{};

  @override
  bool hasPlayed(int messageId) => _played.contains(messageId);

  @override
  void markPlayed(int messageId) => _played.add(messageId);
}
