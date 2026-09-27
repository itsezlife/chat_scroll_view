import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';

/// Where a chat opens: at a message with an alignment, or at a saved
/// Center Band.
sealed class ChatOpenPosition {
  const ChatOpenPosition();

  /// Opens with [ChatScrollController.jumpTo] on [anchor] at [alignment];
  /// [unreadBoundary] is the row that carries the unread separator, if any,
  /// and [tailFitFraction] the jump's tail-or-target fraction, if any.
  const factory ChatOpenPosition.message({
    required int anchor,
    required double alignment,
    required int? unreadBoundary,
    double? tailFitFraction,
  }) = MessageOpenPosition;

  /// Opens with [ChatScrollController.jumpToCenterBand] on [centerBand];
  /// [pendingBoundaryFrom] is the id a pending unread boundary searches
  /// from, if any.
  const factory ChatOpenPosition.centerBand({
    required ChatCenterBand centerBand,
    required int? pendingBoundaryFrom,
  }) = CenterBandOpenPosition;
}

/// An open at a message: the unread boundary at the unread alignment, the
/// tail, or the last-read message.
final class MessageOpenPosition extends ChatOpenPosition {
  /// Opens at [anchor] with [alignment], the separator on [unreadBoundary].
  const MessageOpenPosition({
    required this.anchor,
    required this.alignment,
    required this.unreadBoundary,
    this.tailFitFraction,
  });

  /// Message id handed to [ChatScrollController.jumpTo].
  final int anchor;

  /// Band alignment of [anchor] (`0` = band top, `1` = band bottom).
  final double alignment;

  /// Boundary row of the open, or `null` for no unread separator.
  final int? unreadBoundary;

  /// `tailFitFraction` handed to [ChatScrollController.jumpTo]: the open
  /// lands at the tail instead of [anchor] when the span from [anchor]'s
  /// body to the newest message fits in this fraction of the viewport.
  /// `null` for a plain jump.
  final double? tailFitFraction;
}

/// An open that restores the reading position the reader left.
final class CenterBandOpenPosition extends ChatOpenPosition {
  /// Restores [centerBand]; the boundary is pending from
  /// [pendingBoundaryFrom].
  const CenterBandOpenPosition({
    required this.centerBand,
    required this.pendingBoundaryFrom,
  });

  /// Saved Center Band, applied as one layout navigation.
  final ChatCenterBand centerBand;

  /// First unread id: the pending boundary resolves to the first loaded
  /// incoming message at or after it. `null` when nothing is unread.
  final int? pendingBoundaryFrom;
}

/// Demo helpers for opening a chat at the user's reading position and for
/// deciding what to keep when leaving it.
extension ChatDataSourceX on ChatDataSource {
  /// Alignment for an open at the last-read message: low in the band, so the
  /// messages after it show below.
  static const double _lastReadAlignment = 0.8;

  /// Band alignment of the unread boundary row when the chat opens at it,
  /// page-down navigates to it, or the app resumes onto a boundary moved in
  /// the background: the separator starts at the band top.
  static const double unreadBoundaryAlignment = 0;

  /// Tail-or-target fraction of an open at the unread boundary: unread
  /// content that fits in half the viewport opens at the tail instead.
  static const double unreadBoundaryTailFitFraction = 0.5;

  /// Newer messages after the newest visible one that [resolveLeavePosition]
  /// inspects for an incoming message.
  static const int _leaveLookahead = 4;

  /// The viewport's chunk size. [fetchRange] accepts only whole-chunk ranges.
  static const int _chunkSize = 64;

  /// Where to open the chat and which message carries the unread separator.
  ///
  /// With a [savedCenterBand] the chat restores it: the result is a
  /// [CenterBandOpenPosition] whose pending boundary starts right after
  /// [storedLastRead] (clamped to [oldestKnownId]), or none when
  /// [storedLastRead] is `null` or at or past [newestKnownId]. This path
  /// never fetches; the pending boundary resolves as its rows load.
  ///
  /// Without one the result is a [MessageOpenPosition]. With an unread
  /// boundary (see [resolveUnreadBoundary]) the chat opens at it with
  /// [unreadBoundaryAlignment] and [unreadBoundaryTailFitFraction], so short
  /// unread content opens at the tail. Otherwise it opens at
  /// [resolveOpenAnchor], with no tail-or-target fraction:
  /// at the tail with alignment `0`, or at the last-read message low in the
  /// band. A failed boundary fetch is logged and the chat opens without a
  /// boundary.
  Future<ChatOpenPosition> resolveOpenPosition({
    required int? storedLastRead,
    required bool Function(IChatMessage message) isSelfMessage,
    ChatCenterBand? savedCenterBand,
  }) async {
    if (savedCenterBand case final centerBand?) {
      final newest = newestKnownId;
      final pendingFrom = switch ((storedLastRead, newest)) {
        (final lastRead?, final newest?) when lastRead < newest => math.max(
          lastRead + 1,
          oldestKnownId ?? 0,
        ),
        _ => null,
      };
      return ChatOpenPosition.centerBand(
        centerBand: centerBand,
        pendingBoundaryFrom: pendingFrom,
      );
    }
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
      return ChatOpenPosition.message(
        anchor: boundary,
        alignment: unreadBoundaryAlignment,
        unreadBoundary: boundary,
        tailFitFraction: unreadBoundaryTailFitFraction,
      );
    }
    final newest = newestKnownId;
    final anchor = resolveOpenAnchor(
      storedLastRead: storedLastRead,
      newestKnownId: newest,
      oldestKnownId: oldestKnownId,
    );
    return ChatOpenPosition.message(
      anchor: anchor,
      alignment: anchor == newest ? 0.0 : _lastReadAlignment,
      unreadBoundary: null,
    );
  }

  /// The Center Band to keep for the next open when the reader leaves the
  /// chat, or `null` to drop any saved one.
  ///
  /// `null` when:
  ///
  /// - [isAtTail] is `true` — a chat left at the tail reopens at the tail;
  /// - [centerBand] is `null` — no message sits under the center-band ray;
  /// - the newest visible message [newestVisibleId] is unread incoming (not
  ///   own and after [readMark]) and one of the next four loaded messages
  ///   after it is incoming — the reader stopped at the start of unread
  ///   content, so the next open goes to the unread boundary instead.
  ///
  /// The look-ahead walks loaded messages only, skipping confirmed-absent
  /// ids, and stops at the first id that is not loaded. A `null`
  /// [readMark] counts nothing as unread.
  ChatCenterBand? resolveLeavePosition({
    required ChatCenterBand? centerBand,
    required bool isAtTail,
    required int newestVisibleId,
    required int? readMark,
    required bool Function(IChatMessage message) isSelfMessage,
  }) {
    if (isAtTail) return null;
    final bottom = getMessage(newestVisibleId);
    final bottomUnread = switch ((bottom, readMark)) {
      (final message?, final mark?) =>
        message.id > mark && !isSelfMessage(message),
      _ => false,
    };
    if (bottomUnread) {
      var message = getNextPresentMessage(newestVisibleId);
      for (var step = 0; step < _leaveLookahead && message != null; step++) {
        if (!isSelfMessage(message)) return null;
        message = getNextPresentMessage(message.id);
      }
    }
    return centerBand;
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
