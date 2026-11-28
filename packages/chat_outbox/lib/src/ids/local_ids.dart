import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/ids/provisional_tail_order.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';

/// The id strategy for a backend with global or UUID ids: the host numbers
/// every row of the chat with its own sequential local ids and keeps the
/// server's id in its message model, never in the row's id.
///
/// No id is proposed to the server and no id conflicts. Outgoing rows sit at
/// `tip+1 … tip+k` and move as under `SequentialServerIds`. The host numbers
/// an incoming message from [nextIncomingId] and hands it to [incoming]: by
/// default it lands above the sending rows, which move up.
///
/// With [appendIncoming] the incoming message goes after the outgoing rows
/// instead: [incoming] takes nothing (the host inserts the message at
/// [nextIncomingId], past the rows) and the rows above it settle. A confirmed
/// row above them ends the provisional tail, so a settled row keeps its
/// position for good: it is no longer moved to `tip+1` at publish, does not
/// sink when it fails, and [remove] leaves its removal to the host. Rows
/// placed after the appended message form a new tail.
final class LocalIds implements OutgoingIdStrategy {
  /// The strategy of [chatId], writing [tail].
  LocalIds({
    required String chatId,
    required OutgoingTailTarget tail,
    this.appendIncoming = false,
  }) : _order = ProvisionalTailOrder(
         chatId: chatId,
         strategy: 'localIds',
         target: tail,
       );

  final ProvisionalTailOrder _order;

  /// Whether an incoming message goes after the outgoing rows instead of
  /// above them.
  final bool appendIncoming;

  @override
  String get name => _order.strategy;

  @override
  int get tip => _order.tip;

  /// None: the server's id lives in the host's model.
  @override
  int? get proposedId => null;

  /// The local id the host gives the next incoming message: `tip+1` while
  /// outgoing rows wait (they move up past it), otherwise, or with
  /// [appendIncoming], the id after the newest row.
  int get nextIncomingId => appendIncoming || _order.isEmpty
      ? _order.target.nextInsertId
      : _order.start;

  @override
  List<String> get tail => _order.tail;

  @override
  Map<String, int> get rebases => _order.rebaseCounts;

  @override
  int? positionOf(String clientMessageId) => _order.positionOf(clientMessageId);

  @override
  int allocate(
    String clientMessageId,
    IChatMessage Function(int position) row, {
    bool failed = false,
    bool restored = false,
  }) =>
      _order.allocate(clientMessageId, row, failed: failed, restored: restored);

  @override
  bool incoming(List<IChatMessage> messages) {
    if (!appendIncoming) return _order.insertBefore(messages);
    if (!_order.isEmpty) _order.settleBeforeAppend(messages);
    return false;
  }

  @override
  void publishStart(String clientMessageId) =>
      _order.publishStart(clientMessageId);

  @override
  void fail(String clientMessageId) => _order.fail(clientMessageId);

  @override
  void retry(String clientMessageId) => _order.retry(clientMessageId);

  @override
  bool remove(String clientMessageId) => _order.remove(clientMessageId);

  @override
  Set<String> removeAll(List<String> clientMessageIds) =>
      _order.removeAll(clientMessageIds);

  @override
  int? confirm(String clientMessageId) => _order.confirm(clientMessageId);
}
