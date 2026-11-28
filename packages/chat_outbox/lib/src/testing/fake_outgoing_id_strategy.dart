import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/ids/provisional_tail_order.dart';
import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_outbox/src/testing/fake_outgoing_tail.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';

/// An [OutgoingIdStrategy] for tests of the code that drives one: it keeps
/// the tail's order as the shipped strategies do, over a [FakeOutgoingTail]
/// unless given a target, and records every call in [calls].
final class FakeOutgoingIdStrategy implements OutgoingIdStrategy {
  /// A strategy for chat [chatId] writing [tail], or a fresh
  /// [FakeOutgoingTail] whose newest confirmed message is 100; it proposes
  /// `tip+1` unless [proposesIds] is false.
  factory FakeOutgoingIdStrategy({
    ChatId chatId = const ChatId('c1'),
    OutgoingTailTarget? tail,
    bool proposesIds = true,
  }) => FakeOutgoingIdStrategy._(
    chatId,
    tail ?? FakeOutgoingTail(),
    proposesIds: proposesIds,
  );

  FakeOutgoingIdStrategy._(
    ChatId chatId,
    this.target, {
    required this.proposesIds,
  }) : _order = ProvisionalTailOrder(
         chatId: chatId,
         strategy: 'fake',
         target: target,
       );

  final ProvisionalTailOrder _order;

  /// The rows the strategy writes.
  final OutgoingTailTarget target;

  /// Whether [proposedId] answers `tip+1` rather than null.
  final bool proposesIds;

  /// Every call so far, oldest first: the method's name and the client
  /// message id (`incoming` lists the message ids), then `failed` /
  /// `restored` when an allocation set them.
  final List<String> calls = [];

  @override
  String get name => _order.strategy;

  @override
  int get tip => _order.tip;

  @override
  int? get proposedId => proposesIds ? _order.start : null;

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
  }) {
    calls.add(
      [
        'allocate $clientMessageId',
        if (failed) 'failed',
        if (restored) 'restored',
      ].join(' '),
    );
    return _order.allocate(
      clientMessageId,
      row,
      failed: failed,
      restored: restored,
    );
  }

  @override
  bool incoming(List<IChatMessage> messages) {
    calls.add('incoming ${messages.map((message) => message.id).join(' ')}');
    return _order.insertBefore(messages);
  }

  @override
  void publishStart(ClientMessageId clientMessageId) {
    calls.add('publishStart $clientMessageId');
    _order.publishStart(clientMessageId);
  }

  @override
  void fail(ClientMessageId clientMessageId) {
    calls.add('fail $clientMessageId');
    _order.fail(clientMessageId);
  }

  @override
  void retry(ClientMessageId clientMessageId) {
    calls.add('retry $clientMessageId');
    _order.retry(clientMessageId);
  }

  @override
  bool remove(ClientMessageId clientMessageId) {
    calls.add('remove $clientMessageId');
    return _order.remove(clientMessageId);
  }

  @override
  Set<ClientMessageId> removeAll(List<ClientMessageId> clientMessageIds) {
    calls.add('removeAll ${clientMessageIds.join(' ')}');
    return _order.removeAll(clientMessageIds);
  }

  @override
  int? confirm(ClientMessageId clientMessageId) {
    calls.add('confirm $clientMessageId');
    return _order.confirm(clientMessageId);
  }
}
