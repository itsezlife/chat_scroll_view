import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';

/// Demo helpers for opening a chat at the user's last-read position.
extension ChatDataSourceX on ChatDataSource {
  /// Resolves the message id to pass to [ChatScrollController.jumpTo] on open.
  ///
  /// Prefers [storedLastRead] when it still exists in the loaded cache;
  /// walks backward through loaded ids when the stored row was deleted;
  /// clamps to [oldestKnownId] / [newestKnownId] when boundaries are known.
  int resolveOpenAnchor({
    required int? storedLastRead,
    required int? newestKnownId,
    required int? oldestKnownId,
  }) {
    if (newestKnownId == null) return 0;
    if (storedLastRead == null) return newestKnownId;
    if (storedLastRead >= newestKnownId) return newestKnownId;

    final oldest = oldestKnownId ?? 0;
    if (storedLastRead < oldest) return oldest;

    if (getMessage(storedLastRead) != null) return storedLastRead;

    // Walk backward only through loaded messages to recover from a confirmed
    // deletion. If nothing in [oldest, storedLastRead) is loaded yet
    // (metadata-only connect), trust the stored id — the viewport fetch
    // loads the surrounding chunk on jumpTo.
    for (var id = storedLastRead - 1; id >= oldest; id--) {
      if (getMessage(id) != null) return id;
    }
    return storedLastRead;
  }
}
