import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OutgoingIdStrategyContract.run((tail) => FakeOutgoingIdStrategy(tail: tail));

  test('records every call in order, by client message id', () {
    final strategy = FakeOutgoingIdStrategy();

    strategy
      ..allocate(
        const ClientMessageId('a'),
        (position) => FakeTailMessage(position, 'a'),
      )
      ..allocate(
        const ClientMessageId('b'),
        (position) => FakeTailMessage(position, 'b'),
        failed: true,
        restored: true,
      )
      ..incoming([FakeTailMessage(101)])
      ..publishStart(const ClientMessageId('a'))
      ..fail(const ClientMessageId('a'))
      ..retry(const ClientMessageId('a'))
      ..remove(const ClientMessageId('b'))
      ..confirm(const ClientMessageId('a'));

    expect(strategy.calls, [
      'allocate a',
      'allocate b failed restored',
      'incoming 101',
      'publishStart a',
      'fail a',
      'retry a',
      'remove b',
      'confirm a',
    ]);
  });

  test('keeps its own tail when none is given, from tip 100', () {
    final strategy = FakeOutgoingIdStrategy();

    expect(
      strategy.allocate(
        const ClientMessageId('a'),
        (position) => FakeTailMessage(position, 'a'),
      ),
      101,
    );
    expect(
      strategy.target,
      isA<FakeOutgoingTail>().having((t) => t.provisional, 'provisional', [
        'a',
      ]),
    );
    expect(strategy.name, 'fake');
  });
}
