import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';

/// The **unread boundary** of one chat open, as the listenable handed to
/// [ChatScrollView.unreadBoundary] and to the sender run policy.
///
/// The host drives the boundary: during one open it may set the boundary,
/// move it, make it pending, or clear it, any number of times and in any
/// order. Reading progress (the scroll-to-bottom badge baseline, persisted
/// last-read) is a separate host value: this controller never reads or
/// writes it, and it never writes this one.
///
/// ## Arrivals
///
/// Each advance of [ChatDataSource.newestKnownId] past the newest id already
/// judged is judged once. An arrived message that is loaded and passes
/// `isSelfMessage` — an own message, from this device or another — clears
/// the boundary, pending or not. Every other arrival leaves it alone, at
/// the tail or scrolled up: at the tail the viewport
/// follows the new messages and the separator scrolls away with the rows
/// above them. An arrival that is not loaded when its id becomes known is
/// judged as not own, and loading it later does not judge it again.
///
/// ## Deletions and reads elsewhere
///
/// Every [RemoveBatchMutation] from the data source clears the boundary,
/// pending or not, whichever ids it removes — loaded, unloaded, or far from
/// the boundary row. Update mutations (edits) leave it alone.
///
/// Every notification of the `readElsewhere` listenable clears it too,
/// whatever read id the change stored. Reading progress on this device
/// never reaches the controller, so it never clears the boundary; the
/// source behind `readElsewhere` MUST drop echoes of this client's own read
/// writes.
///
/// ## Pending boundary
///
/// [setPendingBoundary] names where unread content starts before the row
/// that carries the separator is known. The boundary becomes the first
/// message at or after the pending id that is loaded and does not pass
/// `isSelfMessage`; confirmed-absent ids and loaded own messages are
/// skipped. The search runs when the pending boundary is set and again on
/// every data source change, and ends in one of three ways:
///
/// - it finds that message: [value] becomes its id, and the viewport paints
///   the separator when that row is built as a loaded message;
/// - it meets an id that is not loaded yet: the boundary stays pending;
/// - it passes [ChatDataSource.newestKnownId] while
///   [ChatDataSource.reachedNewest] is `true`: the pending boundary lapses.
///   Messages that arrive later never resolve it.
///
/// While pending, [value] is `null`.
///
/// ## Separator seen
///
/// [separatorSeen] becomes `true` on the first
/// [ChatScrollController.visibleRange] push that has the boundary row, as a
/// loaded message, between its first and last id — a layout that built the
/// row with the separator. It stays `true` until [value] changes; every new
/// boundary starts unseen.
///
/// ## Listeners
///
/// Listeners follow the host controller contract: registering the same
/// callback twice is a no-op, dispatch iterates a snapshot, and only a
/// change of [value] notifies — once per change. [separatorSeen] flips
/// without notifying.
final class UnreadBoundaryController implements ValueListenable<int?> {
  /// Starts the open with [boundary] (`null` for none) and begins judging
  /// arrivals and deletions in [dataSource], the visible range of
  /// [controller], and [readElsewhere].
  ///
  /// Arrivals count from [ChatDataSource.newestKnownId] at construction:
  /// messages already known when the open resolved are never judged.
  ///
  /// [readElsewhere] notifies once per read-state change for this chat that
  /// this client did not write; `null` when the source has no shared read
  /// state. The controller only listens to it and never disposes it.
  UnreadBoundaryController({
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    required bool Function(IChatMessage message) isSelfMessage,
    int? boundary,
    Listenable? readElsewhere,
  }) : _dataSource = dataSource,
       _controller = controller,
       _isSelfMessage = isSelfMessage,
       _readElsewhere = readElsewhere,
       _state = switch (boundary) {
         final id? => _BoundaryState.placed(id),
         null => const _BoundaryState.none(),
       },
       _judgedNewestId = dataSource.newestKnownId {
    _dataSource
      ..addBoundaryListener(_onNewestKnownChanged)
      ..addDataListener(_onDataChanged)
      ..addMutationListener(_onMutation);
    _controller.visibleRange.addListener(_judgeSeen);
    _readElsewhere?.addListener(clear);
  }

  final ChatDataSource _dataSource;
  final ChatScrollController _controller;
  final bool Function(IChatMessage message) _isSelfMessage;
  final Listenable? _readElsewhere;

  /// Newest known id already judged; arrivals are the ids above it.
  int? _judgedNewestId;

  _BoundaryState _state;

  final _listeners = <VoidCallback>[];
  bool _disposed = false;

  /// Message id of the boundary row, or `null` when there is none — never
  /// set, cleared, pending, or lapsed.
  @override
  int? get value => _state.id;

  /// Whether the reader has seen the separator of the current boundary.
  ///
  /// `false` whenever [value] is `null`. See the class overview for when it
  /// becomes `true`.
  bool get separatorSeen => switch (_state) {
    _PlacedBoundary(:final seen) => seen,
    _NoBoundary() || _PendingBoundary() => false,
  };

  @override
  void addListener(VoidCallback listener) {
    if (_disposed || _listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Makes message [id] the boundary row, replacing any pending boundary.
  ///
  /// The viewport paints the separator above [id] once that row is built as
  /// a loaded message. A write of the current [value] is silent and keeps
  /// [separatorSeen]. No-op after [dispose].
  void setBoundary(int id) {
    if (_disposed) return;
    _transition(_BoundaryState.placed(id));
  }

  /// Makes the boundary pending from message [fromId] — see the class
  /// overview for how it resolves or lapses.
  ///
  /// When the search resolves at once, [value] moves straight to the found
  /// id; otherwise the current boundary is cleared. A later [setBoundary],
  /// [clear], own arrival, or pending write replaces it. No-op after
  /// [dispose].
  void setPendingBoundary(int fromId) {
    if (_disposed) return;
    _transition(_search(fromId));
  }

  /// Removes the boundary, pending or not. Silent when there is none. No-op
  /// after [dispose].
  void clear() {
    if (_disposed) return;
    _transition(const _BoundaryState.none());
  }

  /// Stops judging arrivals, deletions, reads elsewhere, and separator
  /// visibility, and drops every listener. The value freezes; later writes,
  /// data source changes, range pushes, and read-elsewhere notifications are
  /// ignored. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dataSource
      ..removeBoundaryListener(_onNewestKnownChanged)
      ..removeDataListener(_onDataChanged)
      ..removeMutationListener(_onMutation);
    _controller.visibleRange.removeListener(_judgeSeen);
    _readElsewhere?.removeListener(clear);
    _listeners.clear();
  }

  void _onMutation(ChatMutation mutation) {
    if (mutation case RemoveBatchMutation()) clear();
  }

  void _onNewestKnownChanged() {
    final judged = _judgedNewestId;
    final newest = _dataSource.newestKnownId;
    _judgedNewestId = newest;
    final arrived = switch ((judged, newest)) {
      (final judged?, final newest?) when newest > judged => (
        judged + 1,
        newest,
      ),
      (null, final newest?) => (newest, newest),
      _ => null,
    };
    if (arrived case (final fromId, final toId)) _judgeArrivals(fromId, toId);
  }

  /// Judges arrived ids [fromId]..[toId] — see the class overview.
  void _judgeArrivals(int fromId, int toId) {
    for (var id = fromId; id <= toId; id++) {
      final message = _dataSource.getMessage(id);
      if (message != null && _isSelfMessage(message)) clear();
    }
  }

  void _onDataChanged() {
    if (_state case _PendingBoundary(:final fromId)) {
      _transition(_search(fromId));
    }
  }

  /// Where a pending search from [fromId] stands now: placed at the first
  /// loaded message that is not own, still pending at an id that is not
  /// loaded, or lapsed past the reached newest.
  ///
  /// The walk follows present ids up to [ChatDataSource.newestKnownId],
  /// which is never confirmed absent — so a walk that stops short of it has
  /// met an unloaded id.
  _BoundaryState _search(int fromId) {
    var searched = fromId - 1;
    var message = _dataSource.getNextPresentMessage(searched);
    while (message != null && _isSelfMessage(message)) {
      searched = message.id;
      message = _dataSource.getNextPresentMessage(searched);
    }
    if (message case final incoming?) {
      return _BoundaryState.placed(incoming.id);
    }
    final lapsed = switch (_dataSource.newestKnownId) {
      final newest? => searched >= newest && _dataSource.reachedNewest,
      null => _dataSource.reachedNewest,
    };
    return lapsed
        ? const _BoundaryState.none()
        : _BoundaryState.pending(fromId);
  }

  void _judgeSeen() {
    if (_state case _PlacedBoundary(:final id, seen: false)) {
      if (_controller.visibleRange.value case final range?
          when range.firstId <= id &&
              id <= range.lastId &&
              _dataSource.getMessage(id) != null) {
        _state = _BoundaryState.placed(id, seen: true);
      }
    }
  }

  /// Moves to [next], notifying when [value] changes. Placing the id that
  /// is already placed keeps the current state, and with it
  /// [separatorSeen].
  void _transition(_BoundaryState next) {
    final previous = _state;
    if ((previous, next) case (
      _PlacedBoundary(id: final placed),
      _PlacedBoundary(:final id),
    ) when placed == id) {
      return;
    }
    _state = next;
    if (previous.id == next.id) return;
    for (final listener in List.of(_listeners, growable: false)) {
      listener();
    }
  }
}

/// Where the boundary of one open stands: none, pending from an id, or
/// placed on a row — so a pending search and a placed row, or a seen flag
/// without a row, can never coexist.
sealed class _BoundaryState {
  const _BoundaryState();

  const factory _BoundaryState.none() = _NoBoundary;

  const factory _BoundaryState.pending(int fromId) = _PendingBoundary;

  const factory _BoundaryState.placed(int id, {bool seen}) = _PlacedBoundary;

  /// The boundary row id the viewport paints, or `null`.
  abstract final int? id;
}

final class _NoBoundary extends _BoundaryState {
  const _NoBoundary();

  @override
  int? get id => null;
}

final class _PendingBoundary extends _BoundaryState {
  const _PendingBoundary(this.fromId);

  /// Id the search for the first loaded incoming message starts from.
  final int fromId;

  @override
  int? get id => null;
}

final class _PlacedBoundary extends _BoundaryState {
  const _PlacedBoundary(this.id, {this.seen = false});

  @override
  final int id;

  /// Whether a visible range push has shown this row with the separator.
  final bool seen;
}
