import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:content_assets/content_assets.dart' show ContentKeyMedia;
import 'package:content_model/content_model.dart';
import 'package:message_media/message_media.dart'
    show LinkPreviewHitPart, MediaItemAction;
import 'package:mpx_library/mpx_library.dart';

/// Where a save started: a message menu over one item, a menu over a whole
/// album, the selection bar, or the media viewer.
enum ChatSaveSource {
  /// A message menu over one item.
  menu,

  /// A message menu over every item of an album.
  album,

  /// The selection bar, over the selected messages.
  selection,

  /// The media viewer.
  viewer,
}

/// The chat's save entries and the saves they start, headless: which entry
/// a menu, an album or a selection offers, and one [SaveJob] per tap.
///
/// - The entries are [entries]' defaults for the items' kinds, offered only
///   while protection allows the save: [allowedOf] is the items'
///   `MediaItemAction.allowedItemActions`, read each time an entry is asked
///   for, so the selection bar loses its entry as soon as it rebuilds after
///   protection turned on.
/// - A save protection denies by the time it starts (a menu left open while
///   protection turned on, the viewer) starts nothing: [reportDenied]
///   reports it to the chat's denial feedback.
/// - Every save goes through `MediaSaver.saveContent`, which saves a content
///   already local without downloading it (its file is leased first) and
///   downloads the rest: the chat cannot tell which is which.
/// - A burst of taps on one entry starts one job: the same items to the
///   same destination are dropped for [guardWindow] after a save started.
///
/// One per chat screen, disposed with it.
final class ChatMediaSaves {
  /// Saves of the chat [chatId] through [saver].
  ChatMediaSaves({
    required MediaSaver saver,
    required this.chatId,
    required this.entries,
    required List<MediaItem> Function(int messageId) mediaOf,
    required Set<MediaItemAction> Function(int messageId, MediaItem item)
    allowedOf,
    required void Function(int messageId) reportDenied,
    DateTime Function()? now,
  }) : _saver = saver,
       _mediaOf = mediaOf,
       _allowedOf = allowedOf,
       _reportDenied = reportDenied,
       _now = now ?? DateTime.now;

  /// How long the same save ignores further taps after it started.
  static const Duration guardWindow = Duration(milliseconds: 600);

  /// The chat the events name.
  final String chatId;

  /// The entries per kind on this platform.
  final ChatSaveEntries entries;

  final MediaSaver _saver;
  final List<MediaItem> Function(int messageId) _mediaOf;
  final Set<MediaItemAction> Function(int messageId, MediaItem item) _allowedOf;
  final void Function(int messageId) _reportDenied;
  final DateTime Function() _now;

  // The guarded saves by their items and destination: when each started,
  // and the timer that lifts its guard. A timer rather than a clock alone,
  // so the window runs on a test's fake time.
  final Map<String, (DateTime, Timer)> _$guards = {};
  _Offer _$selectionOffer = _Offer.none;
  bool _$disposed = false;

  // Each of these saves; protection denies them all at once.
  static const _saveActions = {
    MediaItemAction.saveToGallery,
    MediaItemAction.saveToDownloads,
    MediaItemAction.saveAs,
  };

  // --- Entries ---

  /// The entry a menu of the message [messageId] offers over [targets]: the
  /// entry of their kind (shared by every item of an album, which then
  /// saves as one batch), or null on a link preview card ([part] a
  /// `LinkPreviewHitPart`), when the items' entries differ, or while
  /// protection denies the save.
  ChatSaveEntry? entryFor(
    int messageId,
    List<MediaItem> targets, {
    Object? part,
  }) {
    final correlation = ChatCorrelation(
      chatId: chatId,
      scrollId: '$messageId',
      mediaItemId: switch (targets) {
        [final item] => item.id.toString(),
        _ => null,
      },
    );
    if (part is LinkPreviewHitPart) {
      _hidden('linkPreviewPart', live: false, correlation: correlation);
      return null;
    }
    final entry = entries.sharedEntryOf(targets.map((item) => item.kind));
    if (entry == null) return null;
    if (!_mayAllSave({messageId: targets})) {
      _hidden('protection', live: false, correlation: correlation);
      return null;
    }
    _offered(
      entry,
      targets,
      batch: targets.length == 1 ? 'single' : 'album',
      correlation: correlation,
    );
    return entry;
  }

  /// The entry of the selection bar over the messages [messageIds]: the
  /// platform's selection entry when every selected message has media and
  /// all of it is files, and protection allows the save; null otherwise.
  ///
  /// Asked on every rebuild of the bar, so it reports only a change of its
  /// answer: an entry protection takes away from a bar that showed it is
  /// hidden `live`.
  ChatSaveEntry? selectionEntryOf(Iterable<int> messageIds) {
    final entry = entries.selection;
    final selected = {for (final id in messageIds) id: _mediaOf(id)};
    final files =
        selected.isNotEmpty &&
        selected.values.every(
          (items) =>
              items.isNotEmpty && items.every((item) => !item.kind.isPicture),
        );
    final offer = switch ((entry, files)) {
      (null, _) || (_, false) => _Offer.none,
      _ when !_mayAllSave(selected) => _Offer.hidden,
      _ => _Offer.offered,
    };
    final previous = _$selectionOffer;
    _$selectionOffer = offer;
    _changed(
      previous,
      offer,
      entry,
      selected.values.expand((items) => items),
      batch: 'selection',
      correlation: ChatCorrelation(chatId: chatId),
    );
    return offer == _Offer.offered ? entry : null;
  }

  /// The media viewer's saves over the message [messageId]'s items, for as
  /// long as one viewer stays open.
  ChatViewerSaves forViewer(int messageId) =>
      ChatViewerSaves._(this, messageId);

  // Reports a change of what a chrome that re-reads its entry on every
  // rebuild (the selection bar, the viewer) offers: an entry protection
  // takes away from a chrome that showed it is hidden `live`.
  void _changed(
    _Offer previous,
    _Offer offer,
    ChatSaveEntry? entry,
    Iterable<MediaItem> items, {
    required String batch,
    required ChatCorrelation correlation,
  }) {
    if (offer == previous) return;
    switch ((offer, entry)) {
      case (_Offer.offered, final entry?):
        _offered(entry, items, batch: batch, correlation: correlation);
      case (_Offer.hidden, _):
        _hidden(
          'protection',
          live: previous == _Offer.offered,
          correlation: correlation,
        );
      case _:
        break;
    }
  }

  bool _mayAllSave(Map<int, List<MediaItem>> selected) =>
      selected.entries.every(
        (message) => message.value.every(
          (item) => _allowedOf(message.key, item).any(_saveActions.contains),
        ),
      );

  void _offered(
    ChatSaveEntry entry,
    Iterable<MediaItem> items, {
    required String batch,
    required ChatCorrelation correlation,
  }) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.save,
    ChatSaveOp.entriesOffered,
    correlation: correlation,
    fields: () => {
      'kind': switch ({for (final item in items) item.kind.value}.toList()) {
        [final kind] => kind,
        _ => 'mixed',
      },
      'platform': entries.platform,
      'destination': entry.destination.name,
      'batch': batch,
    },
  );

  void _hidden(
    String why, {
    required bool live,
    required ChatCorrelation correlation,
  }) => ChatDiagnostics.current.emit(
    ChatEventLevel.info,
    ChatEventCategory.save,
    ChatSaveOp.entriesHidden,
    correlation: correlation,
    fields: () => {'why': why, 'live': live},
  );

  // --- Saves ---

  /// Saves [items] of the message [messageId] to [entry]'s destination as
  /// one job; answers it, or null when the tap was dropped (the guard, a
  /// denied save, after [dispose]).
  SaveJob? save(
    int messageId,
    List<MediaItem> items,
    ChatSaveEntry entry, {
    required ChatSaveSource source,
  }) => _start({messageId: items}, entry, source);

  /// Saves the media of the selected [messageIds] to [entry]'s destination
  /// as one job; answers it, or null when the tap was dropped.
  SaveJob? saveSelection(Iterable<int> messageIds, ChatSaveEntry entry) =>
      _start(
        {for (final id in messageIds) id: _mediaOf(id)},
        entry,
        ChatSaveSource.selection,
      );

  SaveJob? _start(
    Map<int, List<MediaItem>> selected,
    ChatSaveEntry entry,
    ChatSaveSource source,
  ) {
    if (_$disposed) return null;
    final items = [for (final list in selected.values) ...list];
    if (items.isEmpty) return null;
    final scrollId = switch (selected.keys.toList()) {
      [final id] => '$id',
      _ => null,
    };
    for (final MapEntry(key: messageId, value: list) in selected.entries) {
      if (!_mayAllSave({messageId: list})) {
        _reportDenied(messageId);
        ChatDiagnostics.current.emit(
          ChatEventLevel.info,
          ChatEventCategory.save,
          ChatSaveOp.saveDenied,
          correlation: ChatCorrelation(chatId: chatId, scrollId: '$messageId'),
          fields: () => {
            'path': source == ChatSaveSource.viewer ? 'viewer' : 'staleMenu',
          },
        );
        return null;
      }
    }
    final guard = [
      entry.destination.name,
      for (final item in items) item.descriptor.key.mediaKey.encoded,
    ].join('|');
    if (_$guards[guard] case (final started, _)) {
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.save,
        ChatSaveOp.saveDropped,
        correlation: ChatCorrelation(chatId: chatId, scrollId: scrollId),
        fields: () => {'ms': _now().difference(started).inMilliseconds},
      );
      return null;
    }
    _$guards[guard] = (
      _now(),
      Timer(guardWindow, () => _$guards.remove(guard)),
    );
    final job = _saver.saveContent([
      for (final item in items) _requestOf(item),
    ], entry.destination);
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.save,
      ChatSaveOp.saveStarted,
      correlation: ChatCorrelation(
        chatId: chatId,
        scrollId: scrollId,
        mediaItemId: switch (items) {
          [final item] => item.id.toString(),
          _ => null,
        },
        mediaKey: switch (items) {
          [final item] => item.descriptor.key.mediaKey.encoded,
          _ => null,
        },
        jobId: job.id,
      ),
      fields: () => {
        'source': source.name,
        'items': items.length,
        'destination': entry.destination.name,
      },
    );
    return job;
  }

  // The item's content with the name, type and kind it is saved as: the
  // descriptor's, else a default of its kind, since the saver guesses
  // none of them.
  static SaveRequest _requestOf(MediaItem item) {
    final descriptor = item.descriptor;
    final kind = switch (item.kind) {
      MediaItemKind.photo => SaveItemKind.photo,
      MediaItemKind.video => SaveItemKind.video,
      MediaItemKind.animation => SaveItemKind.animation,
      _ => SaveItemKind.file,
    };
    final mimeType =
        descriptor.mimeType ??
        switch (kind) {
          SaveItemKind.photo => 'image/jpeg',
          SaveItemKind.video => 'video/mp4',
          SaveItemKind.animation => 'image/gif',
          SaveItemKind.file => 'application/octet-stream',
        };
    return SaveRequest(
      descriptor.key.mediaKey,
      name: descriptor.fileName ?? '${kind.name}.${_extensionOf(mimeType)}',
      mimeType: mimeType,
      kind: kind,
    );
  }

  static String _extensionOf(String mimeType) =>
      switch (mimeType.split(';').first.trim().toLowerCase()) {
        'image/jpeg' => 'jpg',
        'application/octet-stream' => 'bin',
        final type => type.split('/').last,
      };

  /// Cancels the guards. Idempotent; a job already running finishes.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    for (final (_, timer) in _$guards.values) {
      timer.cancel();
    }
    _$guards.clear();
  }
}

/// The save of one open media viewer over a message's items: the entry of
/// the item shown, read again on every rebuild of the viewer's chrome, and
/// the save it starts.
///
/// The viewer's chrome asks for its actions whenever it rebuilds (a page
/// turn, the controls showing), so the entry is reported only when its
/// answer changes for an item, and an entry protection takes away while
/// the viewer is open is hidden `live`. Made by [ChatMediaSaves.forViewer]
/// when the viewer opens, dropped when it closes; it holds no resource.
final class ChatViewerSaves {
  ChatViewerSaves._(this._saves, this.messageId);

  final ChatMediaSaves _saves;

  /// The message whose items the viewer shows.
  final int messageId;

  // What each item's entry was the last time the chrome asked.
  final Map<MediaItemId, _Offer> _$offers = {};

  /// The entry of [item]: its kind's on this platform, or null while
  /// protection denies the save.
  ChatSaveEntry? entryOf(MediaItem item) {
    final entry = _saves.entries.entryOf(item.kind);
    final offer =
        _saves._mayAllSave({
          messageId: [item],
        })
        ? _Offer.offered
        : _Offer.hidden;
    final previous = _$offers[item.id] ?? _Offer.none;
    _$offers[item.id] = offer;
    _saves._changed(
      previous,
      offer,
      entry,
      [item],
      batch: 'single',
      correlation: ChatCorrelation(
        chatId: _saves.chatId,
        scrollId: '$messageId',
        mediaItemId: item.id.toString(),
      ),
    );
    return offer == _Offer.offered ? entry : null;
  }

  /// Saves [item] where the entry of its kind saves, as one job; answers it,
  /// or null when the tap was dropped (the guard, a save protection denies
  /// by now, after the saves were disposed).
  SaveJob? save(MediaItem item) => _saves.save(
    messageId,
    [item],
    _saves.entries.entryOf(item.kind),
    source: ChatSaveSource.viewer,
  );
}

// What a chrome's entry was at its last rebuild.
enum _Offer { none, offered, hidden }
