import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Why the provisional tail moved: the `reason` of a `tailRebased` event and
/// the key of the snapshot's rebase counters.
///
/// Closed: a reason is added with the path that moves the tail for it.
@internal
enum TailRebaseReason {
  /// Confirmed messages took the positions before the tail.
  incoming,

  /// A row started publishing and moved to `tip+1`.
  publishStart,

  /// Failed rows sank below a sending row.
  failedSink,

  /// A retried row joined the end of the sending rows.
  retry,

  /// Failed rows sank below a sending row placed again after a restart.
  restart,

  /// A row left the tail.
  removed,

  /// The data source put rows before the tail without the strategy (a range
  /// fetch returning rows inside it), and the tail had moved past them.
  fetch,
}

/// The order of one chat's provisional tail and every move of it: the
/// behaviour both shipped id strategies share.
///
/// It holds the rows in their order and the tail's first position; every
/// change of the order goes to the rows through one `rebaseTail`, so the
/// order here and the data source's provisional tail stay the same list.
/// The order keeps one invariant: the sending rows come first, in the order
/// they were placed in (a publishing row moves to the front), then the failed
/// rows in creation order.
@internal
final class ProvisionalTailOrder {
  /// The order of [chatId]'s tail, written through [target]; [strategy] names
  /// the strategy in events.
  ProvisionalTailOrder({
    required this.chatId,
    required this.strategy,
    required this.target,
  });

  /// The chat.
  final ChatId chatId;

  /// The owning strategy's name.
  final String strategy;

  /// The chat's rows.
  final OutgoingTailTarget target;

  final List<_Row> _$rows = [];

  /// Rows that left the moving tail without being confirmed (an appended
  /// message settled them): their positions, which no longer move.
  final Map<ClientMessageId, int> _$settled = {};

  /// The tail's first position; null while the tail is empty, when it is
  /// read from the rows instead.
  int? _$start;

  int _$created = 0;

  /// Moves so far, by reason.
  final Map<TailRebaseReason, int> rebases = {};

  /// The id of the newest confirmed message the tail sits after, as of the
  /// last [sync] or move.
  int get tip => _tip;

  /// The tail's first position, `tip+1`, as of the last [sync] or move.
  int get start => _start;

  int get _tip => (_$start ?? target.nextInsertId) - 1;

  int get _start => _tip + 1;

  /// Reads the tail's first position back from the rows: the data source
  /// may have put confirmed messages before the tail on its own (rows a
  /// range fetch returned inside it go there, the tail shifting past them),
  /// and without this the order's positions, the tip and the next proposal
  /// would stay where they were. Reports the move as `fetch`.
  ///
  /// Every move calls it first; a reader of [tip], [start] or [positionOf]
  /// calls it before reading, since a getter changes nothing. The rows hold
  /// the tail where the order left it after each of its own moves, so it
  /// changes nothing then.
  void sync() {
    final first = switch (_$rows) {
      [final row, ...] => row.id,
      [] => null,
    };
    final current = _$start;
    if (first == null || current == null) return;
    final at = target.positionOf(first);
    if (at == null || at == current) return;
    final before = _positions();
    _$start = at;
    _counted(TailRebaseReason.fetch);
    _report(TailRebaseReason.fetch, before);
  }

  /// Whether the tail holds no row.
  bool get isEmpty => _$rows.isEmpty;

  /// The client message ids in order.
  List<ClientMessageId> get tail => [for (final row in _$rows) row.id];

  /// [rebases] by reason name.
  Map<String, int> get rebaseCounts => {
    for (final MapEntry(:key, :value) in rebases.entries) key.name: value,
  };

  /// The row's position; see [OutgoingIdStrategy.positionOf].
  int? positionOf(ClientMessageId clientMessageId) =>
      _positionOf(clientMessageId);

  int? _positionOf(ClientMessageId clientMessageId) {
    final index = _indexOf(clientMessageId);
    if (index >= 0) return _start + index;
    return _$settled[clientMessageId];
  }

  /// See [OutgoingIdStrategy.allocate].
  int allocate(
    ClientMessageId clientMessageId,
    IChatMessage Function(int position) build, {
    required bool failed,
    required bool restored,
  }) {
    sync();
    assert(
      _positionOf(clientMessageId) == null,
      'allocate: $clientMessageId already has a position',
    );
    final first = _start;
    final row = _Row(clientMessageId, created: _$created++, failed: failed);
    final sending = _sendingCount;
    // A restored row is the user's, but no send of this run: inserted as one,
    // it would pull a reader scrolled into history down to the tail.
    target.insertMessage(build(first + _$rows.length), followSelf: !restored);
    _$start = first;
    _$rows.add(row);
    final before = _positions();
    if (!failed && sending < _$rows.length - 1) {
      _$rows
        ..removeLast()
        ..insert(sending, row);
      _rebase(
        restored ? TailRebaseReason.restart : TailRebaseReason.failedSink,
        before,
        clientMessageId: clientMessageId,
      );
    }
    final position = _positionOf(clientMessageId)!;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.positionAllocated,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        scrollId: '$position',
      ),
      fields: () => {
        'offsetFromTip': position - _tip,
        'strategy': strategy,
        'allocation': restored ? 'restart' : 'new',
      },
    );
    return position;
  }

  /// Places [messages] before the tail; see [OutgoingIdStrategy.incoming].
  bool insertBefore(List<IChatMessage> messages) {
    sync();
    if (_$rows.isEmpty || messages.isEmpty) return false;
    final first = _start;
    final below = [
      for (final message in messages)
        if (message.id < first) message.id,
    ];
    if (below.isNotEmpty) {
      assert(false, 'incoming: $below are below the tail at $first');
      return false;
    }
    final sorted = [...messages]..sort((a, b) => a.id.compareTo(b.id));
    final before = _positions();
    if (sorted.last.id + 1 > first) _$start = sorted.last.id + 1;
    _rebase(TailRebaseReason.incoming, before, insert: sorted);
    return true;
  }

  /// Ends the moving tail before an appended message: every row keeps its
  /// position as settled, and the tail starts over after the message.
  void settleBeforeAppend(List<IChatMessage> messages) {
    sync();
    final first = _start;
    for (final (index, row) in _$rows.indexed) {
      _$settled[row.id] = first + index;
    }
    final settled = _$rows.length;
    _$rows.clear();
    _$start = null;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.incomingAppended,
      correlation: ChatCorrelation(
        chatId: chatId,
        scrollId: switch (messages) {
          [final first, ...] => '${first.id}',
          [] => null,
        },
      ),
      fields: () => {
        'appendIncoming': true,
        'incoming': messages.length,
        'settled': settled,
      },
    );
  }

  /// See [OutgoingIdStrategy.publishStart].
  void publishStart(ClientMessageId clientMessageId) {
    sync();
    final index = _indexOf(clientMessageId);
    if (index < 0) return;
    final row = _$rows[index];
    assert(!row.failed, 'publishStart: $clientMessageId is failed');
    if (index == 0) return;
    final before = _positions();
    _$rows
      ..removeAt(index)
      ..insert(0, row);
    _rebase(
      TailRebaseReason.publishStart,
      before,
      clientMessageId: clientMessageId,
    );
  }

  /// See [OutgoingIdStrategy.fail].
  void fail(ClientMessageId clientMessageId) {
    sync();
    final index = _indexOf(clientMessageId);
    if (index < 0) return;
    final before = _positions();
    final row = _$rows.removeAt(index)..failed = true;
    var at = _$rows.length;
    for (var i = _sendingCount; i < _$rows.length; i++) {
      if (_$rows[i].created > row.created) {
        at = i;
        break;
      }
    }
    _$rows.insert(at, row);
    if (at != index) {
      _rebase(
        TailRebaseReason.failedSink,
        before,
        clientMessageId: clientMessageId,
      );
    }
  }

  /// See [OutgoingIdStrategy.retry].
  void retry(ClientMessageId clientMessageId) {
    sync();
    final index = _indexOf(clientMessageId);
    if (index < 0) return;
    final before = _positions();
    final row = _$rows.removeAt(index)..failed = false;
    final at = _sendingCount;
    _$rows.insert(at, row);
    if (at != index) {
      _rebase(TailRebaseReason.retry, before, clientMessageId: clientMessageId);
    }
  }

  /// See [OutgoingIdStrategy.remove].
  bool remove(ClientMessageId clientMessageId) =>
      removeAll([clientMessageId]).isNotEmpty;

  /// See [OutgoingIdStrategy.removeAll].
  Set<ClientMessageId> removeAll(List<ClientMessageId> clientMessageIds) {
    sync();
    final leaving = {
      for (final id in clientMessageIds)
        if (_indexOf(id) >= 0) id,
    };
    for (final id in clientMessageIds) {
      if (!leaving.contains(id)) _$settled.remove(id);
    }
    if (leaving.isEmpty) return leaving;
    final before = _positions();
    _$rows.removeWhere((row) => leaving.contains(row.id));
    _rebase(
      TailRebaseReason.removed,
      before,
      // One row names itself; a batch names only the rows it moved.
      clientMessageId: leaving.length == 1 ? leaving.single : null,
    );
    if (_$rows.isEmpty) _$start = null;
    return leaving;
  }

  /// See [OutgoingIdStrategy.confirm].
  int? confirm(ClientMessageId clientMessageId) {
    sync();
    if (_$settled.remove(clientMessageId) case final position?) {
      return position;
    }
    final index = _indexOf(clientMessageId);
    if (index < 0) return null;
    if (index > 0) publishStart(clientMessageId);
    final position = _start;
    _$rows.removeAt(0);
    _$start = _$rows.isEmpty ? null : position + 1;
    return position;
  }

  int get _sendingCount {
    var count = 0;
    for (final row in _$rows) {
      if (row.failed) break;
      count++;
    }
    return count;
  }

  int _indexOf(ClientMessageId clientMessageId) =>
      _$rows.indexWhere((row) => row.id == clientMessageId);

  /// The positions of the rows now, by identity: what a move compares
  /// against to report the rows it moved.
  Map<ClientMessageId, int> _positions() => {
    for (final (index, row) in _$rows.indexed) row.id: _start + index,
  };

  /// Writes the current order to the rows in one `rebaseTail` and reports
  /// it; [before] are the positions before the order changed.
  void _rebase(
    TailRebaseReason reason,
    Map<ClientMessageId, int> before, {
    ClientMessageId? clientMessageId,
    List<IChatMessage> insert = const [],
  }) {
    target.rebaseTail(order: tail, insert: insert);
    _counted(reason);
    _report(reason, before, clientMessageId: clientMessageId, insert: insert);
  }

  void _counted(TailRebaseReason reason) =>
      rebases.update(reason, (count) => count + 1, ifAbsent: () => 1);

  /// Reports the move [reason] made from [before]: one event per row whose
  /// position changed, then one for [clientMessageId] when it did not move.
  void _report(
    TailRebaseReason reason,
    Map<ClientMessageId, int> before, {
    ClientMessageId? clientMessageId,
    List<IChatMessage> insert = const [],
  }) {
    final diagnostics = ChatDiagnostics.current;
    if (!diagnostics.isEnabled(ChatEventLevel.debug)) return;
    var triggerMoved = false;
    for (final (index, row) in _$rows.indexed) {
      final to = _start + index;
      final from = before[row.id];
      if (from == null || from == to) continue;
      if (row.id == clientMessageId) triggerMoved = true;
      diagnostics.emit(
        ChatEventLevel.debug,
        ChatEventCategory.outbox,
        OutboxOp.tailRebased,
        correlation: ChatCorrelation(
          chatId: chatId,
          clientMessageId: row.id,
          scrollId: '$to',
        ),
        fields: () => {
          'reason': reason.name,
          'rows': _$rows.length,
          'inserted': insert.length,
          'from': from,
        },
      );
    }
    if (triggerMoved) return;
    diagnostics.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.tailRebased,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        scrollId: switch (clientMessageId == null
            ? null
            : _positionOf(clientMessageId)) {
          final position? => '$position',
          null => null,
        },
      ),
      fields: () => {
        'reason': reason.name,
        'rows': _$rows.length,
        'inserted': insert.length,
      },
    );
  }
}

/// One row of the tail: its identity, when it was placed and whether it
/// failed.
final class _Row {
  _Row(this.id, {required this.created, required this.failed});

  final ClientMessageId id;

  /// The row's place in creation order; failed rows sort by it.
  final int created;

  bool failed;
}
