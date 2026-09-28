import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved reading position of each chat: one [ChatCenterBand] per chat key,
/// kept in [SharedPreferences] across launches.
///
/// A chat key names one conversation and must stay stable across launches;
/// chats that do not share history must not share a key.
final class ChatCenterBandStore {
  ChatCenterBandStore._(this._prefs);

  /// Opens the store over the app's shared preferences.
  static Future<ChatCenterBandStore> open() async =>
      ChatCenterBandStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static String _messageIdKey(String chatKey) =>
      'chat_center_band/$chatKey/message_id';

  static String _offsetKey(String chatKey) =>
      'chat_center_band/$chatKey/offset';

  /// The Center Band saved for [chatKey], or `null` when none is saved.
  ChatCenterBand? read(String chatKey) {
    final messageId = _prefs.getInt(_messageIdKey(chatKey));
    final offset = _prefs.getDouble(_offsetKey(chatKey));
    return switch ((messageId, offset)) {
      (final messageId?, final offset?) => ChatCenterBand(
        messageId: messageId,
        offsetFromMessageTop: offset,
      ),
      _ => null,
    };
  }

  /// Saves [centerBand] for [chatKey], or removes the saved one when
  /// [centerBand] is `null`.
  ///
  /// [read] sees the write as soon as this returns; the returned future
  /// completes when it reaches the platform store.
  Future<void> write(String chatKey, ChatCenterBand? centerBand) async {
    switch (centerBand) {
      case ChatCenterBand(:final messageId, :final offsetFromMessageTop):
        await (
          _prefs.setInt(_messageIdKey(chatKey), messageId),
          _prefs.setDouble(_offsetKey(chatKey), offsetFromMessageTop),
        ).wait;
      case null:
        await (
          _prefs.remove(_messageIdKey(chatKey)),
          _prefs.remove(_offsetKey(chatKey)),
        ).wait;
    }
  }
}
