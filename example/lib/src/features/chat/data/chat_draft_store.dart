import 'dart:convert';

import 'package:chat_composer/chat_composer.dart'
    show LinkPreviewDismissalState;
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The operation of the `linkPreview` diagnostics event [ChatDraftStore]
/// emits.
enum ChatDraftOp implements DiagnosticOp {
  /// A stored record could not be read (warning): `errorType`, the kind of
  /// problem (`noBody`). The record is ignored.
  draftDecodeFailed,
}

/// The unsent state of one chat's composer: the markdown the wire would
/// carry, the message being edited when the composer was in edit mode, and
/// the link preview fields.
@immutable
final class ChatDraft {
  /// A draft of [markdown], for editing message [editing] when it is not
  /// null, with the link preview fields of [linkPreview].
  const ChatDraft({
    required this.markdown,
    this.editing,
    this.linkPreview = ChatLinkPreviewDraft.empty,
  });

  /// The composer's text as markdown, with the blanks the user left in it.
  final String markdown;

  /// The id of the message the draft edits, or null for a new message.
  final int? editing;

  /// The link preview's options, the message's `invertMedia` and the
  /// dismissal state.
  final ChatLinkPreviewDraft linkPreview;

  @override
  bool operator ==(Object other) =>
      other is ChatDraft &&
      other.markdown == markdown &&
      other.editing == editing &&
      other.linkPreview == linkPreview;

  @override
  int get hashCode => Object.hash(markdown, editing, linkPreview);

  @override
  String toString() => 'ChatDraft(editing: $editing, ${markdown.length} chars)';
}

/// The link preview fields of a draft: the options, the message's
/// [invertMedia] and the dismissal state, which is never sent.
@immutable
final class ChatLinkPreviewDraft {
  /// The fields of a draft.
  const ChatLinkPreviewDraft({
    this.options,
    this.invertMedia = false,
    this.dismissal,
  });

  /// Nothing to keep.
  static const ChatLinkPreviewDraft empty = ChatLinkPreviewDraft();

  /// The options of the preview the draft showed, if any.
  final LinkPreviewOptions? options;

  /// Whether the message puts its media above its text.
  final bool invertMedia;

  /// What the dismissal had turned off; null when nothing.
  final LinkPreviewDismissalState? dismissal;

  /// Whether there is nothing to keep.
  bool get isEmpty => options == null && !invertMedia && dismissal == null;

  @override
  bool operator ==(Object other) =>
      other is ChatLinkPreviewDraft &&
      other.options == options &&
      other.invertMedia == invertMedia &&
      other.dismissal == dismissal;

  @override
  int get hashCode => Object.hash(options, invertMedia, dismissal);
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
/// the id of another. The record is a JSON object (version 2):
///
/// ```text
/// { body: markdown, editing?: id, linkPreview?: { url, media, removed },
///   invertMedia?: true, dismissal?: { policy, dismissed?, urls? } }
/// ```
///
/// `linkPreview` and `invertMedia` are `LinkPreviewWire`'s fields, without a
/// page (a restored draft looks its link up again); `dismissal` is the
/// composer-only `LinkPreviewDismissalState`, never sent. A record of
/// version 1 (the edited message's id on the first line, the markdown after
/// it) and a version 2 value that is a plain string, not an object, read as
/// a draft of that text alone; there is no migration.
final class ChatDraftStore {
  /// A store over [storage].
  ChatDraftStore(this._storage);

  /// The key-value namespace of every record.
  static const String namespace = 'chat_draft';

  /// The schema version of a record written now; a record of a version
  /// other than this and [legacyVersion] is ignored.
  static const int version = 2;

  /// The version of the records written before the link preview fields.
  static const int legacyVersion = 1;

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
    return switch (stored) {
      StoredValue(version: legacyVersion, :final value) => _decodeLegacy(value),
      StoredValue(version: version, :final value) => _decode(value, chatKey),
      _ => null,
    };
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
      final draft => _storage.write(
        namespace,
        chatKey,
        StoredValue(jsonEncode(_encode(draft)), version: version),
      ),
    };
  }

  static Map<String, Object?> _encode(ChatDraft draft) {
    final ChatDraft(:markdown, :editing, :linkPreview) = draft;
    final record = <String, Object?>{'body': markdown, 'editing': ?editing};
    LinkPreviewWire.write(
      record,
      linkPreview: switch (linkPreview.options) {
        final options? => MessageLinkPreview(options: options),
        null => null,
      },
      invertMedia: linkPreview.invertMedia,
    );
    if (linkPreview.dismissal case final dismissal?) {
      record['dismissal'] = dismissal.toJson();
    }
    return record;
  }

  static ChatDraft? _decode(String value, String chatKey) {
    final Object? json;
    try {
      json = jsonDecode(value);
    } on FormatException {
      // A plain string is a draft of that text.
      return ChatDraft(markdown: value);
    }
    switch (json) {
      case final Map<String, Object?> record:
        if (record['body'] case final String body) {
          return ChatDraft(
            markdown: body,
            editing: switch (record['editing']) {
              final int id => id,
              _ => null,
            },
            linkPreview: ChatLinkPreviewDraft(
              options: LinkPreviewWire.readLinkPreview(record)?.options,
              invertMedia: LinkPreviewWire.readInvertMedia(record),
              dismissal: LinkPreviewDismissalState.fromJson(
                record['dismissal'],
              ),
            ),
          );
        }
        ChatDiagnostics.current.emit(
          ChatEventLevel.warning,
          ChatEventCategory.linkPreview,
          ChatDraftOp.draftDecodeFailed,
          correlation: ChatCorrelation(chatId: chatKey),
          fields: () => {'errorType': 'noBody'},
        );
        return null;
      case final String body:
        return ChatDraft(markdown: body);
      case _:
        // JSON that is no record (a number, a list) is still text.
        return ChatDraft(markdown: value);
    }
  }

  static ChatDraft? _decodeLegacy(String record) {
    final split = record.indexOf('\n');
    if (split < 0) return null;
    final header = record.substring(0, split);
    final editing = header.isEmpty ? null : int.tryParse(header);
    if (header.isNotEmpty && editing == null) return null;
    return ChatDraft(markdown: record.substring(split + 1), editing: editing);
  }
}
