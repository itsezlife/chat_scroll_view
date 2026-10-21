import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_draft_store.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:flutter/foundation.dart';

/// Keeps one chat's [ChatDraftStore] record equal to its composer: written a
/// moment after the text or the edit target changes, removed when the
/// composer is empty and not editing.
///
/// The write is debounced because a record is the whole markdown and a
/// keystroke changes it: typing costs one write when the user pauses, not one
/// per key. [flush] writes at once for the moments the user may not come back
/// to (leaving the chat, the app hiding), [discard] drops the record when a
/// send has made the draft a message.
///
/// A write that fails is logged and retried on the next change or flush; the
/// composer never waits on storage.
final class ChatDraftSync {
  /// Starts keeping [chatKey]'s record equal to [composer] and [editing].
  ///
  /// [saved] is what the store holds now, so a draft just restored is not
  /// written back unchanged.
  ChatDraftSync({
    required this.store,
    required this.chatKey,
    required this.composer,
    required this.editing,
    required this.editingId,
    required ChatDraft? saved,
    this.debounce = defaultDebounce,
  }) : _saved = saved {
    composer.text.addListener(_onChange);
    editing.addListener(_onChange);
    // Text typed before the record was read differs from it already.
    if (_current() != _saved) _onChange();
  }

  /// How long the composer must be still before its draft is written.
  static const Duration defaultDebounce = Duration(milliseconds: 500);

  /// The store written to.
  final ChatDraftStore store;

  /// The chat the record belongs to.
  final String chatKey;

  /// The composer whose text is the draft.
  final ComposerController composer;

  /// Notifies when the message being edited changes.
  final Listenable editing;

  /// The id of the message being edited, or null; part of the draft.
  final int? Function() editingId;

  /// The pause before a change is written.
  final Duration debounce;

  Timer? _timer;
  ChatDraft? _saved;
  var _failed = false;
  var _disposed = false;

  void _onChange() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  /// Writes the composer's draft now, unless the store already holds it.
  void flush() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _save(_current());
  }

  /// Removes the record at once and cancels a pending write: the draft was
  /// sent.
  void discard() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _save(null);
  }

  /// Writes what is pending and stops listening.
  void dispose() {
    if (_disposed) return;
    flush();
    _disposed = true;
    composer.text.removeListener(_onChange);
    editing.removeListener(_onChange);
  }

  // Drafts are composer state, not a wire body: no detection, no trim, and a
  // unicode emoji keeps its reference, so what comes back is what was there.
  ChatDraft? _current() {
    final text = composer.richText;
    final target = editingId();
    if (text.isEmpty && target == null) return null;
    return ChatDraft(
      markdown: ChatBodyMarkdown.encodeDraft(text),
      editing: target,
    );
  }

  void _save(ChatDraft? draft) {
    if (draft == _saved && !_failed) return;
    _saved = draft;
    _failed = false;
    unawaited(
      store.write(chatKey, draft).catchError((Object error, StackTrace stack) {
        _failed = true;
        dev.log(
          'Saving the draft failed',
          name: 'chat_draft',
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }
}
