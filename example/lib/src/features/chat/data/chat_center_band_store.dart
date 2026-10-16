import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';

/// Saved reading position of each chat: one [ChatCenterBand] per chat key,
/// kept in the host's [KeyValueStore] across launches.
///
/// A chat key names one conversation and must stay stable across launches;
/// chats that do not share history must not share a key. It is a key-value
/// name, so it uses the alphabet of one (letters, digits, `_`, `.`, `-`).
///
/// Positions saved by the previous store (plain `shared_preferences` keys) are
/// not read: the first open of a chat after the move has no saved position.
final class ChatCenterBandStore {
  /// A store over [storage].
  ChatCenterBandStore(this._storage);

  /// The key-value namespace of every record.
  static const String namespace = 'chat_center_band';

  /// The schema version of a record; a record of another version is ignored.
  static const int version = 1;

  final KeyValueStore _storage;

  // The latest write per chat. A read sees a write at once, whether or not
  // the platform has it yet: the platform store may reorder an in-flight
  // write behind a read.
  final Map<String, ChatCenterBand?> _written = <String, ChatCenterBand?>{};

  /// The Center Band saved for [chatKey], or `null` when none is saved or the
  /// record cannot be read.
  ///
  /// Throws an [ArgumentError] for a [chatKey] outside the key-value name
  /// alphabet.
  Future<ChatCenterBand?> read(String chatKey) async {
    if (_written.containsKey(chatKey)) return _written[chatKey];
    final stored = await _storage.read(namespace, chatKey);
    if (_written.containsKey(chatKey)) return _written[chatKey];
    return stored == null || stored.version != version
        ? null
        : _decode(stored.value);
  }

  /// Saves [centerBand] for [chatKey], or removes the saved one when
  /// [centerBand] is `null`.
  ///
  /// [read] sees the write as soon as this is called; the returned future
  /// completes when it reaches the platform store.
  Future<void> write(String chatKey, ChatCenterBand? centerBand) {
    _written[chatKey] = centerBand;
    return switch (centerBand) {
      null => _storage.remove(namespace, chatKey),
      ChatCenterBand(:final messageId, :final offsetFromMessageTop) =>
        _storage.write(
          namespace,
          chatKey,
          StoredValue('$messageId:$offsetFromMessageTop', version: version),
        ),
    };
  }

  static ChatCenterBand? _decode(String text) {
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final messageId = int.tryParse(parts[0]);
    final offset = double.tryParse(parts[1]);
    if (messageId == null || offset == null || !offset.isFinite) return null;
    return ChatCenterBand(messageId: messageId, offsetFromMessageTop: offset);
  }
}
