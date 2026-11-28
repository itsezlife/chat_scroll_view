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

  /// The client message ids of the provisional tail in order, lowest
  /// position first.
  List<String> get tail;

  /// The current position of the row [clientMessageId], or null when the
  /// strategy holds no such row.
  ///
  /// A provisional row's position moves with the tail; the host addresses
  /// the row by it (an `updateMessage` passes a message whose id is this
  /// position).
  int? positionOf(String clientMessageId);

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
    String clientMessageId,
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
  void publishStart(String clientMessageId);

  /// The row [clientMessageId] failed: it sinks below every sending row,
  /// among the failed rows in creation order.
  void fail(String clientMessageId);

  /// The failed row [clientMessageId] is retried: it joins the end of the
  /// sending rows, above the rows still failed.
  void retry(String clientMessageId);

  /// The row [clientMessageId] leaves (cancelled or deleted): the rows after
  /// it move down and its last position becomes Absent, in one
  /// `rebaseTail`.
  ///
  /// Answers whether the row was in the tail. False for a row the strategy
  /// no longer moves (no such row, or one an appended message settled): the
  /// host removes that row itself.
  bool remove(String clientMessageId);

  /// The row [clientMessageId] is confirmed and leaves the tail; answers the
  /// position it was confirmed at, or null when the strategy holds no such
  /// row.
  ///
  /// A row that is not at `tip+1` moves there first, so the confirmed
  /// message sits right after the tip. The host then replaces the row at
  /// that position with the confirmed message (for which `identityOf`
  /// answers null).
  int? confirm(String clientMessageId);
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

  /// Inserts a new row (`ChatDataSource.insertMessage`).
  void insertMessage(IChatMessage message);

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
  void insertMessage(IChatMessage message) => _source.insertMessage(message);

  @override
  void rebaseTail({
    required List<Object> order,
    List<IChatMessage> insert = const [],
  }) => _source.rebaseTail(order: order, insert: insert);
}
