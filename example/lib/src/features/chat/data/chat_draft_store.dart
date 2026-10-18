import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The unsent text of one chat's composer: the markdown the wire would carry,
/// and the message being edited when the composer was in edit mode.
@immutable
final class ChatDraft {
  /// A draft of [markdown], for editing message [editing] when it is not null.
  const ChatDraft({required this.markdown, this.editing});

  /// The composer's text as markdown, with the blanks the user left in it.
  final String markdown;

  /// The id of the message the draft edits, or null for a new message.
  final int? editing;

  @override
  bool operator ==(Object other) =>
      other is ChatDraft &&
      other.markdown == markdown &&
      other.editing == editing;

  @override
  int get hashCode => Object.hash(markdown, editing);

  @override
  String toString() => 'ChatDraft(editing: $editing, ${markdown.length} chars)';
}

/// Drafts of the chats, one [ChatDraft] per chat key, kept in the host's
/// [KeyValueStore] across launches (ADR 023: the host owns persistence).
///
/// A chat key names one conversation and must stay stable across launches. It
/// is a key-value name, so it uses the alphabet of one (letters, digits, `_`,
/// `.`, `-`). A draft is the markdown the wire carries, not `RichText.toJson`,
/// so a draft and a sent body decode through one codec.
///
/// ## Record
///
/// One record per chat, so a crash cannot leave the text of one edit beside
/// the id of another: the first line is the edited message's id (empty for a
/// new message), the rest is the markdown.
final class ChatDraftStore {
  /// A store over [storage].
  ChatDraftStore(this._storage);

  /// The key-value namespace of every record.
  static const String namespace = 'chat_draft';

  /// The schema version of a record; a record of another version is ignored.
  static const int version = 1;

  final KeyValueStore _storage;

  // The latest write per chat. A read sees a write at once, whether or not the
  // platform has it yet: leaving a chat writes, and opening it again reads,
  // and the platform store may reorder an in-flight write behind a read.
  final Map<String, ChatDraft?> _written = <String, ChatDraft?>{};

  /// The draft saved for [chatKey], or null when none is saved or the record
  /// cannot be read.
  ///
  /// Throws an [ArgumentError] for a [chatKey] outside the key-value name
  /// alphabet.
  Future<ChatDraft?> read(String chatKey) async {
    if (_written.containsKey(chatKey)) return _written[chatKey];
    final stored = await _storage.read(namespace, chatKey);
    if (_written.containsKey(chatKey)) return _written[chatKey];
    return stored == null || stored.version != version
        ? null
        : _decode(stored.value);
  }

  /// Saves [draft] for [chatKey], or removes the saved one when [draft] is
  /// null.
  ///
  /// [read] sees the write as soon as this is called; the returned future
  /// completes when it reaches the platform store.
  Future<void> write(String chatKey, ChatDraft? draft) {
    _written[chatKey] = draft;
    return switch (draft) {
      null => _storage.remove(namespace, chatKey),
      ChatDraft(:final markdown, :final editing) => _storage.write(
        namespace,
        chatKey,
        StoredValue('${editing ?? ''}\n$markdown', version: version),
      ),
    };
  }

  static ChatDraft? _decode(String record) {
    final split = record.indexOf('\n');
    if (split < 0) return null;
    final header = record.substring(0, split);
    final editing = header.isEmpty ? null : int.tryParse(header);
    if (header.isNotEmpty && editing == null) return null;
    return ChatDraft(markdown: record.substring(split + 1), editing: editing);
  }
}
