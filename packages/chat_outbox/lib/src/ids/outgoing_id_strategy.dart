import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';

/// Where the outgoing rows of one chat take their ids and move: the
/// `allocate` / `rebase` seam of the provisional tail (ADR 048, ADR 001
/// amendment).
///
/// The provisional tail is the run of outgoing rows after the newest
/// confirmed message, at `tip+1 … tip+k`. A row's id there is a position, not
/// its identity: the identity is the client message id, and every method
/// here names a row by it. Sending rows keep creation order among
/// themselves; failed rows sit below every sending row, in creation order
/// among themselves, so a failed message always sits at the bottom of the
/// chat.
///
/// A strategy belongs to one chat and writes through that chat's
/// [OutgoingTailTarget]: a new row with an insert, every move with one
/// `rebaseTail`. Two strategies ship, `SequentialServerIds` and `LocalIds`; a
/// host may supply its own, held to `OutgoingIdStrategyContract`
/// (`testing.dart`).
abstract interface class OutgoingIdStrategy {
  /// The strategy's stable name, for diagnostics and the debug snapshot.
  String get name;

  /// The id of the newest confirmed message the tail sits after.
  int get tip;

  /// The id the sender proposes to the server for the row publishing now,
  /// read at publish time and never stored: the next server id, `tip+1`.
  /// Null for a strategy that proposes none (the server's id is the host's,
  /// in its model), whose sender gets no proposal and no conflict.
  int? get proposedId;

  /// The client message ids of the provisional tail in order, lowest
  /// position first.
  List<ClientMessageId> get tail;

  /// The moves of the tail so far by reason (`incoming`, `publishStart`,
  /// `failedSink`, `retry`, `restart`, `removed`, `fetch`), for the debug
  /// snapshot.
  Map<String, int> get rebases;

  /// The current position of the row [clientMessageId], or null when the
  /// strategy holds no such row.
  ///
  /// A provisional row's position moves with the tail; the host addresses
  /// the row by it (an `updateMessage` passes a message whose id is this
  /// position). As of the last [sync] or move: reading it changes nothing.
  int? positionOf(ClientMessageId clientMessageId);

  /// Brings the strategy up to the rows: the data source may have put
  /// confirmed messages before the tail on its own (a range fetch's rows
  /// inside it), which moves the tail's first position, and with it [tip],
  /// [proposedId] and every [positionOf]. Reports such a move as `fetch`.
  ///
  /// Every move here does it first. A reader of the getters calls it before
  /// reading (the outbox does at each of its entry points), so no getter has
  /// a side effect.
  void sync();

  /// Places a new outgoing row [clientMessageId] and returns its position.
  ///
  /// [row] builds the host's message for the position the row is inserted
  /// at; the strategy inserts it. A sending row goes after the other sending
  /// rows, so when failed rows sit at the bottom it is inserted at the end
  /// and they sink below it in the same frame. A [failed] row goes to the
  /// bottom. [restored] marks a row placed again after a restart, which
  /// takes a fresh position like a new one: the caller allocates the sending
  /// rows first, then the failed ones, each in creation order.
  int allocate(
    ClientMessageId clientMessageId,
    IChatMessage Function(int position) row, {
    bool failed = false,
    bool restored = false,
  });

  /// Takes confirmed [messages] that land inside the provisional tail (a
  /// peer's message at `tip+1`): they take the positions before the tail and
  /// the tail moves up, in one `rebaseTail`. The host's duty: hand every
  /// incoming message whose id falls inside the tail here instead of
  /// inserting it.
  ///
  /// Answers whether the strategy placed them. False when there is no tail
  /// to move (or, under a strategy that appends incoming messages, always):
  /// the host then inserts [messages] itself as usual.
  bool incoming(List<IChatMessage> messages);

  /// The row [clientMessageId] starts publishing: it moves to `tip+1`,
  /// above every other row, so the message the server accepts sits right
  /// after the tip.
  void publishStart(ClientMessageId clientMessageId);

  /// The row [clientMessageId] failed: it sinks below every sending row,
  /// among the failed rows in creation order.
  void fail(ClientMessageId clientMessageId);

  /// The failed row [clientMessageId] is retried: it joins the end of the
  /// sending rows, above the rows still failed.
  void retry(ClientMessageId clientMessageId);

  /// The row [clientMessageId] leaves (cancelled or deleted): the rows after
  /// it move down and its last position becomes Absent, in one
  /// `rebaseTail`.
  ///
  /// Answers whether the row was in the tail. False for a row the strategy
  /// no longer moves (no such row, or one an appended message settled): the
  /// host removes that row itself.
  bool remove(ClientMessageId clientMessageId);

  /// The rows [clientMessageIds] leave together (a cancel of every job in
  /// the system's transfer envelope): as [remove], with every row gone in
  /// one `rebaseTail`, so the chat lays out once rather than once per row.
  ///
  /// Answers the ids whose rows were in the tail; the host removes any
  /// other row itself, as after [remove]. Moves nothing when it answers
  /// none.
  Set<ClientMessageId> removeAll(List<ClientMessageId> clientMessageIds);

  /// The row [clientMessageId] is confirmed and leaves the tail; answers the
  /// position it was confirmed at, or null when the strategy holds no such
  /// row.
  ///
  /// A row that is not at `tip+1` moves there first, so the confirmed
  /// message sits right after the tip. The host then replaces the row at
  /// that position with the confirmed message (for which `identityOf`
  /// answers null).
  int? confirm(ClientMessageId clientMessageId);
}

/// The one chat's rows an [OutgoingIdStrategy] writes: the narrow part of
/// the chat's `ChatDataSource` it needs.
///
/// [OutgoingTailTarget.of] adapts a data source; tests use
/// `FakeOutgoingTail` (`testing.dart`).
abstract interface class OutgoingTailTarget {
  /// The target over [source], whose `identityOf` the host has set.
  factory OutgoingTailTarget.of(ChatDataSource source) = _DataSourceTail;

  /// The next id after the newest row that is neither present nor pending
  /// removal (`ChatDataSource.nextInsertId`).
  int get nextInsertId;

  /// The position of the provisional row whose identity is [identity] (its
  /// client message id), or null when the tail holds none: where the data
  /// source holds it now, which a move the strategy did not make (rows a
  /// range fetch put before the tail) may have changed.
  int? positionOf(Object identity);

  /// Inserts a new row (`ChatDataSource.insertMessage`). [followSelf] false
  /// is a row placed again after a restart: the viewport does not pull a
  /// reader scrolled up to it, as it does for the user's new message.
  void insertMessage(IChatMessage message, {bool followSelf = true});

  /// Moves the provisional tail in one atomic step
  /// (`ChatDataSource.rebaseTail`).
  void rebaseTail({
    required List<Object> order,
    List<IChatMessage> insert = const [],
  });
}

final class _DataSourceTail implements OutgoingTailTarget {
  _DataSourceTail(this._source);

  final ChatDataSource _source;

  @override
  int get nextInsertId => _source.nextInsertId;

  @override
  int? positionOf(Object identity) {
    final identityOf = _source.identityOf;
    if (identityOf == null) return null;
    // The tail is the run of provisional rows down from the newest one, a
    // handful of rows: walk it.
    for (var id = _source.nextInsertId - 1; ; id--) {
      final key = switch (_source.getMessage(id)) {
        final message? => identityOf(message),
        null => null,
      };
      if (key == null) return null;
      if (key == identity) return id;
    }
  }

  @override
  void insertMessage(IChatMessage message, {bool followSelf = true}) =>
      _source.insertMessage(message, followSelf: followSelf);

  @override
  void rebaseTail({
    required List<Object> order,
    List<IChatMessage> insert = const [],
  }) => _source.rebaseTail(order: order, insert: insert);
}
