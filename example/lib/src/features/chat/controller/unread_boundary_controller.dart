import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';

/// The **unread boundary** of one chat open, as the listenable handed to
/// [ChatScrollView.unreadBoundary].
///
/// The value is the snapshot taken at open — the first incoming message
/// after the stored last-read — and never advances while the reader catches
/// up. Reading progress (the scroll-to-bottom badge baseline, persisted
/// last-read) is a separate host value: this controller never reads or
/// writes it, and it never writes this one.
///
/// While a boundary is set, each advance of [ChatDataSource.newestKnownId]
/// past the newest id already seen is judged once:
///
/// - any arrived message that is loaded and passes `isSelfMessage` (an own
///   send, from any device) clears the boundary;
/// - otherwise, arriving while [ChatScrollController.isAtTail] is `true`
///   clears it — the reader sees the new messages as they land;
/// - otherwise (the reader is scrolled up) the boundary stays.
///
/// A cleared boundary stays cleared for the rest of the open. A new open
/// is a new controller.
///
/// Listeners follow the host controller contract: registering the same
/// callback twice is a no-op, dispatch iterates a snapshot, and only a
/// value change notifies.
final class UnreadBoundaryController implements ValueListenable<int?> {
  /// Snapshots [boundary] for this open and starts judging arrivals in
  /// [dataSource] against [controller]'s tail state.
  ///
  /// Arrivals count from [ChatDataSource.newestKnownId] at construction:
  /// messages already known when the open resolved never clear the
  /// boundary.
  UnreadBoundaryController({
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    required bool Function(IChatMessage message) isSelfMessage,
    int? boundary,
  }) : _dataSource = dataSource,
       _controller = controller,
       _isSelfMessage = isSelfMessage,
       _value = boundary,
       _seenNewestId = dataSource.newestKnownId {
    _dataSource.addBoundaryListener(_onNewestKnownChanged);
  }

  final ChatDataSource _dataSource;
  final ChatScrollController _controller;
  final bool Function(IChatMessage message) _isSelfMessage;

  /// Newest known id already judged; arrivals are the ids above it.
  int? _seenNewestId;

  final _listeners = <VoidCallback>[];
  bool _disposed = false;

  int? _value;

  /// Message id of the boundary row, or `null` once cleared (or when the
  /// open had no unread incoming message).
  @override
  int? get value => _value;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed || _listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Stops judging arrivals and drops every listener. The value freezes;
  /// later data source changes are ignored. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dataSource.removeBoundaryListener(_onNewestKnownChanged);
    _listeners.clear();
  }

  void _onNewestKnownChanged() {
    final seen = _seenNewestId;
    final newest = _dataSource.newestKnownId;
    _seenNewestId = newest;
    final arrived = switch ((seen, newest)) {
      (final seen?, final newest?) when newest > seen => (seen + 1, newest),
      (null, final newest?) => (newest, newest),
      _ => null,
    };
    if (arrived case (final fromId, final toId) when _value != null) {
      if (_controller.isAtTail.value || _hasOwnMessage(fromId, toId)) {
        _clear();
      }
    }
  }

  bool _hasOwnMessage(int fromId, int toId) {
    for (var id = fromId; id <= toId; id++) {
      if (_dataSource.getMessage(id) case final message?
          when _isSelfMessage(message)) {
        return true;
      }
    }
    return false;
  }

  void _clear() {
    _value = null;
    for (final listener in List.of(_listeners, growable: false)) {
      listener();
    }
  }
}
