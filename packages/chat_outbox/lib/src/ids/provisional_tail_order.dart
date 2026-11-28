import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
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
  final String chatId;

  /// The owning strategy's name.
  final String strategy;

  /// The chat's rows.
  final OutgoingTailTarget target;

  final List<_Row> _$rows = [];

  /// Rows that left the moving tail without being confirmed (an appended
  /// message settled them): their positions, which no longer move.
  final Map<String, int> _$settled = {};

  /// The tail's first position; null while the tail is empty, when it is
  /// read from the rows instead.
  int? _$start;

  int _$created = 0;

  /// Moves so far, by reason.
  final Map<TailRebaseReason, int> rebases = {};

  /// The id of the newest confirmed message the tail sits after.
  int get tip => (_$start ?? target.nextInsertId) - 1;

  /// The tail's first position, `tip+1`.
  int get start => tip + 1;

  /// Whether the tail holds no row.
  bool get isEmpty => _$rows.isEmpty;

  /// The client message ids in order.
  List<String> get tail => [for (final row in _$rows) row.id];

  /// [rebases] by reason name.
  Map<String, int> get rebaseCounts => {
    for (final MapEntry(:key, :value) in rebases.entries) key.name: value,
  };

  /// The row's position; see [OutgoingIdStrategy.positionOf].
  int? positionOf(String clientMessageId) {
    final index = _indexOf(clientMessageId);
    if (index >= 0) return start + index;
    return _$settled[clientMessageId];
  }

  /// See [OutgoingIdStrategy.allocate].
  int allocate(
    String clientMessageId,
    IChatMessage Function(int position) build, {
    required bool failed,
    required bool restored,
  }) {
    assert(
      positionOf(clientMessageId) == null,
      'allocate: $clientMessageId already has a position',
    );
    final first = start;
    final row = _Row(clientMessageId, created: _$created++, failed: failed);
    final sending = _sendingCount;
    target.insertMessage(build(first + _$rows.length));
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
    final position = positionOf(clientMessageId)!;
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
        'offsetFromTip': position - tip,
        'strategy': strategy,
        'allocation': restored ? 'restart' : 'new',
      },
    );
    return position;
  }

  /// Places [messages] before the tail; see [OutgoingIdStrategy.incoming].
  bool insertBefore(List<IChatMessage> messages) {
    if (_$rows.isEmpty || messages.isEmpty) return false;
    final first = start;
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
    final first = start;
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
  void publishStart(String clientMessageId) {
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
  void fail(String clientMessageId) {
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
  void retry(String clientMessageId) {
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
  bool remove(String clientMessageId) {
    final index = _indexOf(clientMessageId);
    if (index < 0) {
      _$settled.remove(clientMessageId);
      return false;
    }
    final before = _positions();
    _$rows.removeAt(index);
    _rebase(TailRebaseReason.removed, before, clientMessageId: clientMessageId);
    if (_$rows.isEmpty) _$start = null;
    return true;
  }

  /// See [OutgoingIdStrategy.confirm].
  int? confirm(String clientMessageId) {
    if (_$settled.remove(clientMessageId) case final position?) {
      return position;
    }
    final index = _indexOf(clientMessageId);
    if (index < 0) return null;
    if (index > 0) publishStart(clientMessageId);
    final position = start;
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

  int _indexOf(String clientMessageId) =>
      _$rows.indexWhere((row) => row.id == clientMessageId);

  /// The positions of the rows now, by identity: what a move compares
  /// against to report the rows it moved.
  Map<String, int> _positions() => {
    for (final (index, row) in _$rows.indexed) row.id: start + index,
  };

  /// Writes the current order to the rows in one `rebaseTail` and reports
  /// it; [before] are the positions before the order changed.
  void _rebase(
    TailRebaseReason reason,
    Map<String, int> before, {
    String? clientMessageId,
    List<IChatMessage> insert = const [],
  }) {
    target.rebaseTail(order: tail, insert: insert);
    rebases.update(reason, (count) => count + 1, ifAbsent: () => 1);
    final diagnostics = ChatDiagnostics.current;
    if (!diagnostics.isEnabled(ChatEventLevel.debug)) return;
    var triggerMoved = false;
    for (final (index, row) in _$rows.indexed) {
      final to = start + index;
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
        scrollId: switch (positionOf(clientMessageId ?? '')) {
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

  final String id;

  /// The row's place in creation order; failed rows sort by it.
  final int created;

  bool failed;
}
