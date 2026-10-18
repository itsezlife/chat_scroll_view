/// Which animated stickers a chat screen has already played, per message.
///
/// A lone unicode emoji plays its animation once, the first time the screen
/// shows it, and then rests on a frame (Telegram Android's
/// `alreadyPlayedStickers`); a tap plays it again. The memory is the chat
/// screen's, not the asset cache's: the cache is shared by every screen and
/// keeps no per-chat history (ADR 029, per-chat controllers). A new screen has
/// a new memory, so a chat reopened later plays its stickers again, as on
/// Android.
final class StickerPlayMemory {
  final Set<int> _played = <int>{};

  /// Whether the sticker of message [messageId] may play now: true the first
  /// time it is asked for, false ever after.
  ///
  /// The caller asks once when the body mounts and keeps the answer for the
  /// life of that mount. Asking again on each build would hold a sticker that
  /// is still playing.
  bool claimFirstPlay(int messageId) => _played.add(messageId);
}
