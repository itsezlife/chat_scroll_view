import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/ids/provisional_tail_order.dart';
import 'package:chat_outbox/src/testing/fake_outgoing_tail.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';

/// An [OutgoingIdStrategy] for tests of the code that drives one: it keeps
/// the tail's order as the shipped strategies do, over a [FakeOutgoingTail]
/// unless given a target, and records every call in [calls].
final class FakeOutgoingIdStrategy implements OutgoingIdStrategy {
  /// A strategy for chat [chatId] writing [tail], or a fresh
  /// [FakeOutgoingTail] whose newest confirmed message is 100.
  factory FakeOutgoingIdStrategy({
    String chatId = 'c1',
    OutgoingTailTarget? tail,
  }) => FakeOutgoingIdStrategy._(chatId, tail ?? FakeOutgoingTail());

  FakeOutgoingIdStrategy._(String chatId, this.target)
    : _order = ProvisionalTailOrder(
        chatId: chatId,
        strategy: 'fake',
        target: target,
      );

  final ProvisionalTailOrder _order;

  /// The rows the strategy writes.
  final OutgoingTailTarget target;

  /// Every call so far, oldest first: the method's name and the client
  /// message id (`incoming` lists the message ids), then `failed` /
  /// `restored` when an allocation set them.
  final List<String> calls = [];

  @override
  String get name => _order.strategy;

  @override
  int get tip => _order.tip;

  @override
  List<String> get tail => _order.tail;

  @override
  int? positionOf(String clientMessageId) => _order.positionOf(clientMessageId);

  @override
  int allocate(
    String clientMessageId,
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
  void publishStart(String clientMessageId) {
    calls.add('publishStart $clientMessageId');
    _order.publishStart(clientMessageId);
  }

  @override
  void fail(String clientMessageId) {
    calls.add('fail $clientMessageId');
    _order.fail(clientMessageId);
  }

  @override
  void retry(String clientMessageId) {
    calls.add('retry $clientMessageId');
    _order.retry(clientMessageId);
  }

  @override
  bool remove(String clientMessageId) {
    calls.add('remove $clientMessageId');
    return _order.remove(clientMessageId);
  }

  @override
  int? confirm(String clientMessageId) {
    calls.add('confirm $clientMessageId');
    return _order.confirm(clientMessageId);
  }
}
