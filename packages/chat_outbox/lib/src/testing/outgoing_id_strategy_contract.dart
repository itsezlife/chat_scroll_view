import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_outbox/src/testing/fake_outgoing_tail.dart';
import 'package:flutter_test/flutter_test.dart';

/// The behaviour every [OutgoingIdStrategy] must have, as a test suite to
/// run against an implementation.
abstract final class OutgoingIdStrategyContract {
  /// Runs the contract against the strategies [create] returns over a fresh
  /// [FakeOutgoingTail] whose newest confirmed message is 100.
  ///
  /// [appendsIncoming] is for a strategy that appends incoming messages at
  /// the end instead of placing them before the tail: its `incoming` takes
  /// nothing and the rows above stop being moved.
  static void run(
    OutgoingIdStrategy Function(FakeOutgoingTail tail) create, {
    bool appendsIncoming = false,
  }) {
    group('OutgoingIdStrategy contract', () {
      late FakeOutgoingTail tail;
      late OutgoingIdStrategy strategy;

      setUp(() {
        tail = FakeOutgoingTail();
        strategy = create(tail);
      });

      int allocate(String id, {bool failed = false, bool restored = false}) =>
          strategy.allocate(
            ClientMessageId(id),
            (position) => FakeTailMessage(position, id),
            failed: failed,
            restored: restored,
          );

      /// The strategy's view and the rows agree.
      void expectTail(List<String> order) {
        expect(strategy.tail, order, reason: 'the strategy order');
        expect(tail.provisional, order, reason: 'the rows');
        for (final (index, id) in order.indexed) {
          expect(
            strategy.positionOf(ClientMessageId(id)),
            strategy.tip + 1 + index,
          );
        }
      }

      group('allocate', () {
        test('rows take tip+1 … tip+k in creation order', () {
          expect(allocate('a'), 101);
          expect(allocate('b'), 102);
          expect(allocate('c'), 103);

          expect(strategy.tip, 100);
          expectTail(['a', 'b', 'c']);
          expect(tail.rebases, isEmpty);
        });

        test('the first row follows the newest message', () {
          tail.insertMessage(FakeTailMessage(101));

          expect(allocate('a'), 102);
          expect(strategy.tip, 101);
        });

        test('a sending row goes above the failed rows, which sink', () {
          allocate('a');
          allocate('b');
          strategy.fail(const ClientMessageId('a'));

          expect(allocate('c'), 102);

          expectTail(['b', 'c', 'a']);
        });

        test('a failed row goes to the bottom', () {
          allocate('a');

          expect(allocate('b', failed: true), 102);
          expect(allocate('c'), 102);

          expectTail(['a', 'c', 'b']);
        });

        test('after a restart: sending in creation order, failed below', () {
          allocate('s1', restored: true);
          allocate('f1', failed: true, restored: true);
          allocate('s2', restored: true);
          allocate('f2', failed: true, restored: true);

          expectTail(['s1', 's2', 'f1', 'f2']);
        });

        test('answers no position for a row it never placed', () {
          expect(strategy.positionOf(const ClientMessageId('nope')), isNull);
        });
      });

      group('publishStart', () {
        test('the publishing row moves to tip+1 in one move', () {
          allocate('a');
          allocate('b');
          allocate('c');

          strategy.publishStart(const ClientMessageId('c'));

          expectTail(['c', 'a', 'b']);
          expect(
            strategy.positionOf(const ClientMessageId('c')),
            strategy.tip + 1,
          );
          expect(tail.rebases, hasLength(1));
        });

        test('a row already at tip+1 does not move', () {
          allocate('a');
          allocate('b');

          strategy.publishStart(const ClientMessageId('a'));

          expectTail(['a', 'b']);
          expect(tail.rebases, isEmpty);
        });

        test('failed rows stay below the publishing row', () {
          allocate('a');
          allocate('b');
          allocate('c');
          strategy.fail(const ClientMessageId('a'));

          strategy.publishStart(const ClientMessageId('c'));

          expectTail(['c', 'b', 'a']);
        });
      });

      group('fail', () {
        test('a failed row sinks below every sending row', () {
          allocate('a');
          allocate('b');
          allocate('c');

          strategy.fail(const ClientMessageId('a'));

          expectTail(['b', 'c', 'a']);
        });

        test('failed rows keep creation order among themselves', () {
          allocate('a');
          allocate('b');
          allocate('c');
          allocate('d');

          strategy
            ..fail(const ClientMessageId('c'))
            ..fail(const ClientMessageId('a'));

          expectTail(['b', 'd', 'a', 'c']);
        });

        test('the last row failing does not move', () {
          allocate('a');
          allocate('b');

          strategy.fail(const ClientMessageId('b'));

          expectTail(['a', 'b']);
          expect(tail.rebases, isEmpty);
        });
      });

      group('retry', () {
        test('a retried row joins the end of the sending rows', () {
          allocate('a');
          allocate('b');
          allocate('c');
          allocate('d');
          strategy
            ..fail(const ClientMessageId('a'))
            ..fail(const ClientMessageId('b'));

          strategy.retry(const ClientMessageId('b'));

          expectTail(['c', 'd', 'b', 'a']);
        });

        test('a retried row that fails again sinks back in creation order', () {
          allocate('a');
          allocate('b');
          allocate('c');
          strategy
            ..fail(const ClientMessageId('a'))
            ..fail(const ClientMessageId('b'))
            ..retry(const ClientMessageId('b'));

          strategy.fail(const ClientMessageId('b'));

          expectTail(['c', 'a', 'b']);
        });
      });

      group('remove', () {
        test('a removed row leaves and the rows after it move down', () {
          allocate('a');
          allocate('b');
          allocate('c');

          expect(strategy.remove(const ClientMessageId('b')), isTrue);

          expectTail(['a', 'c']);
          expect(strategy.positionOf(const ClientMessageId('b')), isNull);
          expect(tail.at(103), isNull);
        });

        test('the next row may take a removed row\'s position', () {
          allocate('a');
          allocate('b');
          strategy.remove(const ClientMessageId('b'));

          expect(allocate('c'), 102);
        });

        test('the last row removed empties the tail', () {
          allocate('a');

          strategy.remove(const ClientMessageId('a'));

          expectTail([]);
          expect(strategy.tip, 100);
          expect(allocate('b'), 101);
        });

        test('answers false for a row it does not hold', () {
          expect(strategy.remove(const ClientMessageId('nope')), isFalse);
          expect(tail.rebases, isEmpty);
        });
      });

      group('removeAll', () {
        test('the rows leave together in one rebaseTail and the rows after '
            'them move down', () {
          allocate('a');
          allocate('b');
          allocate('c');
          allocate('d');

          expect(
            strategy.removeAll([
              const ClientMessageId('b'),
              const ClientMessageId('d'),
              const ClientMessageId('nope'),
            ]),
            {'b', 'd'},
          );

          expectTail(['a', 'c']);
          expect(tail.rebases, hasLength(1));
          expect(strategy.positionOf(const ClientMessageId('b')), isNull);
          expect(strategy.positionOf(const ClientMessageId('d')), isNull);
          expect(tail.at(103), isNull);
          expect(tail.at(104), isNull);
        });

        test('every row removed empties the tail', () {
          allocate('a');
          allocate('b');

          expect(
            strategy.removeAll([
              const ClientMessageId('a'),
              const ClientMessageId('b'),
            ]),
            {'a', 'b'},
          );

          expectTail([]);
          expect(allocate('c'), 101);
        });

        test('answers none and moves nothing for rows it does not hold', () {
          allocate('a');

          expect(strategy.removeAll([const ClientMessageId('nope')]), isEmpty);
          expect(strategy.removeAll([]), isEmpty);
          expect(tail.rebases, isEmpty);
        });
      });

      group('confirm', () {
        test('the confirmed row leaves at tip+1 and the tip advances', () {
          allocate('a');
          allocate('b');
          strategy.publishStart(const ClientMessageId('a'));

          expect(strategy.confirm(const ClientMessageId('a')), 101);
          tail.update(FakeTailMessage(101));

          expect(strategy.tip, 101);
          expectTail(['b']);
          expect(strategy.positionOf(const ClientMessageId('a')), isNull);
        });

        test('a row not at tip+1 moves there first', () {
          allocate('a');
          allocate('b');

          expect(strategy.confirm(const ClientMessageId('b')), 101);
          tail.update(FakeTailMessage(101));

          expectTail(['a']);
          expect(strategy.positionOf(const ClientMessageId('a')), 102);
        });

        test('the only row confirmed leaves the tail empty', () {
          allocate('a');

          expect(strategy.confirm(const ClientMessageId('a')), 101);
          tail.update(FakeTailMessage(101));

          expectTail([]);
          expect(strategy.tip, 101);
          expect(allocate('b'), 102);
        });

        test('answers null for a row it does not hold', () {
          expect(strategy.confirm(const ClientMessageId('nope')), isNull);
        });
      });

      group('rows placed without the strategy', () {
        test('rows the data source put before the tail (a range fetch) move '
            'the strategy\'s positions and tip with it', () {
          allocate('a');
          allocate('b');

          // The data source applies a fetch inside the tail as this move.
          tail.rebaseTail(order: ['a', 'b'], insert: [FakeTailMessage(101)]);
          // A getter reads the strategy as it is: sync brings it to the rows.
          expect(strategy.tip, 100);
          strategy.sync();

          expect(strategy.tip, 101);
          expectTail(['a', 'b']);
          expect(allocate('c'), 104);
          expectTail(['a', 'b', 'c']);
        });
      });

      group('incoming', () {
        test('with no tail it takes nothing', () {
          expect(strategy.incoming([FakeTailMessage(101)]), isFalse);
          expect(tail.rebases, isEmpty);
        });

        if (appendsIncoming) {
          test('an incoming message is left to the host to append', () {
            allocate('a');
            allocate('b');

            expect(strategy.incoming([FakeTailMessage(103)]), isFalse);

            expect(tail.rebases, isEmpty);
            expect(strategy.tail, isEmpty);
            expect(strategy.positionOf(const ClientMessageId('a')), 101);
            expect(strategy.positionOf(const ClientMessageId('b')), 102);
          });
        } else {
          test('an incoming message at tip+1 shifts the tail by one', () {
            allocate('a');
            allocate('b');

            expect(strategy.incoming([FakeTailMessage(101)]), isTrue);

            expect(tail.identityAt(101), 'confirmed');
            expect(strategy.tip, 101);
            expectTail(['a', 'b']);
            expect(tail.rebases.single.inserted, [101]);
          });

          test('several incoming messages land above sending and failed '
              'rows alike', () {
            allocate('a');
            allocate('b');
            strategy.fail(const ClientMessageId('a'));

            strategy.incoming([FakeTailMessage(102), FakeTailMessage(101)]);

            expect(strategy.tip, 102);
            expectTail(['b', 'a']);
          });

          test('a publishing row is still at tip+1 after an incoming one', () {
            allocate('a');
            allocate('b');
            strategy.publishStart(const ClientMessageId('b'));

            strategy.incoming([FakeTailMessage(101)]);

            expect(
              strategy.positionOf(const ClientMessageId('b')),
              strategy.tip + 1,
            );
            expectTail(['b', 'a']);
          });
        }
      });
    });
  }
}
