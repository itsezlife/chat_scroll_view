import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';

/// Demo helpers for opening a chat at the user's last-read position.
extension ChatDataSourceX on ChatDataSource {
  /// Alignment for an open at the last-read message: low in the band, so the
  /// messages after it show below.
  static const double _lastReadAlignment = 0.8;

  /// Band alignment of the unread boundary row when the chat opens at it or
  /// the app resumes onto a boundary moved in the background: the separator
  /// starts at the band top.
  static const double unreadBoundaryAlignment = 0;

  /// The viewport's chunk size. [fetchRange] accepts only whole-chunk ranges.
  static const int _chunkSize = 64;

  /// Where to open the chat and which message carries the unread separator.
  ///
  /// With an unread boundary (see [resolveUnreadBoundary]) the chat opens at
  /// it with [unreadBoundaryAlignment], so the boundary row starts at the
  /// band top. Otherwise it opens at [resolveOpenAnchor]: at the tail with
  /// alignment `0`, or at the last-read message low in the band.
  ///
  /// A failed boundary fetch is logged and the chat opens without a boundary.
  Future<({int anchor, double alignment, int? unreadBoundary})>
  resolveOpenPosition({
    required int? storedLastRead,
    required bool Function(IChatMessage message) isSelfMessage,
  }) async {
    int? boundary;
    try {
      boundary = await resolveUnreadBoundary(
        storedLastRead: storedLastRead,
        isSelfMessage: isSelfMessage,
      );
    } on Object catch (error, stackTrace) {
      dev.log(
        'Unread boundary fetch failed; opening without an unread separator',
        name: 'chat_open',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (boundary != null) {
      return (
        anchor: boundary,
        alignment: unreadBoundaryAlignment,
        unreadBoundary: boundary,
      );
    }
    final newest = newestKnownId;
    final anchor = resolveOpenAnchor(
      storedLastRead: storedLastRead,
      newestKnownId: newest,
      oldestKnownId: oldestKnownId,
    );
    return (
      anchor: anchor,
      alignment: anchor == newest ? 0.0 : _lastReadAlignment,
      unreadBoundary: null,
    );
  }

  /// The unread boundary for an open: the smallest id after [storedLastRead]
  /// whose message is not the signed-in user's ([isSelfMessage], the same
  /// predicate the scroll-to-bottom pill uses).
  ///
  /// `null` without a stored last-read, when it is at or past
  /// [newestKnownId], or when every message after it is own.
  ///
  /// Scans loaded messages in id order. At the first id that is not loaded,
  /// the whole chunk holding it is read with one [fetchRange] call; the
  /// result is not written into the cache. The scan then continues through
  /// loaded messages only and stops at the next unloaded id, so an open
  /// makes at most one fetch. A fetch error propagates.
  Future<int?> resolveUnreadBoundary({
    required int? storedLastRead,
    required bool Function(IChatMessage message) isSelfMessage,
  }) async {
    final newest = newestKnownId;
    if (storedLastRead == null || newest == null) return null;
    var fetched = false;
    var id = math.max(storedLastRead + 1, oldestKnownId ?? 0);
    while (id <= newest) {
      final message = getMessage(id);
      if (message != null) {
        if (!isSelfMessage(message)) return id;
        id++;
        continue;
      }
      if (fetched) return null;
      fetched = true;
      final chunkFirst = id - id % _chunkSize;
      final chunkLast = chunkFirst + _chunkSize - 1;
      final incoming = <int>[
        for (final message in await fetchRange(
          fromId: chunkFirst,
          toId: chunkLast,
        ))
          if (message.id >= id &&
              message.id <= newest &&
              !isSelfMessage(message))
            message.id,
      ];
      if (incoming.isNotEmpty) return incoming.reduce(math.min);
      id = chunkLast + 1;
    }
    return null;
  }

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
