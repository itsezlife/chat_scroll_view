import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/ids/provisional_tail_order.dart';
import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';

/// The id strategy for a server that keeps one sequential id counter per
/// chat and accepts a proposed id only if it is the next one
/// (accept-if-next).
///
/// Outgoing rows sit at `tip+1 … tip+k`. A peer's message that arrives at
/// `tip+1` while they wait is handed to [incoming]: it takes its id and the
/// rows move up by one, so it never overwrites an outgoing row in place. At
/// publish the row moves to `tip+1` ([publishStart]) and the sender proposes
/// [proposedId], read then and never stored: when the server accepts, the
/// row's position is the server's id. A provisional position is a position:
/// after a cancel the next row may take it (ADR 001 amendment); confirmed
/// ids are never reused.
final class SequentialServerIds implements OutgoingIdStrategy {
  /// The strategy of [chatId], writing [tail].
  SequentialServerIds({
    required ChatId chatId,
    required OutgoingTailTarget tail,
  }) : _order = ProvisionalTailOrder(
         chatId: chatId,
         strategy: 'sequentialServerIds',
         target: tail,
       );

  final ProvisionalTailOrder _order;

  @override
  String get name => _order.strategy;

  @override
  int get tip => _order.tip;

  /// The id to propose to the server for the message publishing now: the
  /// next server id, `tip+1`, not the row's position at creation.
  @override
  int get proposedId => _order.start;

  @override
  List<ClientMessageId> get tail => _order.tail;

  @override
  Map<String, int> get rebases => _order.rebaseCounts;

  @override
  int? positionOf(ClientMessageId clientMessageId) =>
      _order.positionOf(clientMessageId);

  @override
  void sync() => _order.sync();

  @override
  int allocate(
    ClientMessageId clientMessageId,
    IChatMessage Function(int position) row, {
    bool failed = false,
    bool restored = false,
  }) =>
      _order.allocate(clientMessageId, row, failed: failed, restored: restored);

  @override
  bool incoming(List<IChatMessage> messages) => _order.insertBefore(messages);

  @override
  void publishStart(ClientMessageId clientMessageId) =>
      _order.publishStart(clientMessageId);

  @override
  void fail(ClientMessageId clientMessageId) => _order.fail(clientMessageId);

  @override
  void retry(ClientMessageId clientMessageId) => _order.retry(clientMessageId);

  @override
  bool remove(ClientMessageId clientMessageId) =>
      _order.remove(clientMessageId);

  @override
  Set<ClientMessageId> removeAll(List<ClientMessageId> clientMessageIds) =>
      _order.removeAll(clientMessageIds);

  @override
  int? confirm(ClientMessageId clientMessageId) =>
      _order.confirm(clientMessageId);
}
