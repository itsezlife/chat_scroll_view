import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
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
            id,
            (position) => FakeTailMessage(position, id),
            failed: failed,
            restored: restored,
          );

      /// The strategy's view and the rows agree.
      void expectTail(List<String> order) {
        expect(strategy.tail, order, reason: 'the strategy order');
        expect(tail.provisional, order, reason: 'the rows');
        for (final (index, id) in order.indexed) {
          expect(strategy.positionOf(id), strategy.tip + 1 + index);
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
          strategy.fail('a');

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
          expect(strategy.positionOf('nope'), isNull);
        });
      });

      group('publishStart', () {
        test('the publishing row moves to tip+1 in one move', () {
          allocate('a');
          allocate('b');
          allocate('c');

          strategy.publishStart('c');

          expectTail(['c', 'a', 'b']);
          expect(strategy.positionOf('c'), strategy.tip + 1);
          expect(tail.rebases, hasLength(1));
        });

        test('a row already at tip+1 does not move', () {
          allocate('a');
          allocate('b');

          strategy.publishStart('a');

          expectTail(['a', 'b']);
          expect(tail.rebases, isEmpty);
        });

        test('failed rows stay below the publishing row', () {
          allocate('a');
          allocate('b');
          allocate('c');
          strategy.fail('a');

          strategy.publishStart('c');

          expectTail(['c', 'b', 'a']);
        });
      });

      group('fail', () {
        test('a failed row sinks below every sending row', () {
          allocate('a');
          allocate('b');
          allocate('c');

          strategy.fail('a');

          expectTail(['b', 'c', 'a']);
        });

        test('failed rows keep creation order among themselves', () {
          allocate('a');
          allocate('b');
          allocate('c');
          allocate('d');

          strategy
            ..fail('c')
            ..fail('a');

          expectTail(['b', 'd', 'a', 'c']);
        });

        test('the last row failing does not move', () {
          allocate('a');
          allocate('b');

          strategy.fail('b');

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
            ..fail('a')
            ..fail('b');

          strategy.retry('b');

          expectTail(['c', 'd', 'b', 'a']);
        });

        test('a retried row that fails again sinks back in creation order', () {
          allocate('a');
          allocate('b');
          allocate('c');
          strategy
            ..fail('a')
            ..fail('b')
            ..retry('b');

          strategy.fail('b');

          expectTail(['c', 'a', 'b']);
        });
      });

      group('remove', () {
        test('a removed row leaves and the rows after it move down', () {
          allocate('a');
          allocate('b');
          allocate('c');

          expect(strategy.remove('b'), isTrue);

          expectTail(['a', 'c']);
          expect(strategy.positionOf('b'), isNull);
          expect(tail.at(103), isNull);
        });

        test('the next row may take a removed row\'s position', () {
          allocate('a');
          allocate('b');
          strategy.remove('b');

          expect(allocate('c'), 102);
        });

        test('the last row removed empties the tail', () {
          allocate('a');

          strategy.remove('a');

          expectTail([]);
          expect(strategy.tip, 100);
          expect(allocate('b'), 101);
        });

        test('answers false for a row it does not hold', () {
          expect(strategy.remove('nope'), isFalse);
          expect(tail.rebases, isEmpty);
        });
      });

      group('confirm', () {
        test('the confirmed row leaves at tip+1 and the tip advances', () {
          allocate('a');
          allocate('b');
          strategy.publishStart('a');

          expect(strategy.confirm('a'), 101);
          tail.update(FakeTailMessage(101));

          expect(strategy.tip, 101);
          expectTail(['b']);
          expect(strategy.positionOf('a'), isNull);
        });

        test('a row not at tip+1 moves there first', () {
          allocate('a');
          allocate('b');

          expect(strategy.confirm('b'), 101);
          tail.update(FakeTailMessage(101));

          expectTail(['a']);
          expect(strategy.positionOf('a'), 102);
        });

        test('the only row confirmed leaves the tail empty', () {
          allocate('a');

          expect(strategy.confirm('a'), 101);
          tail.update(FakeTailMessage(101));

          expectTail([]);
          expect(strategy.tip, 101);
          expect(allocate('b'), 102);
        });

        test('answers null for a row it does not hold', () {
          expect(strategy.confirm('nope'), isNull);
        });
      });

      group('rows placed without the strategy', () {
        test('rows the data source put before the tail (a range fetch) move '
            'the strategy\'s positions and tip with it', () {
          allocate('a');
          allocate('b');

          // The data source applies a fetch inside the tail as this move.
          tail.rebaseTail(order: ['a', 'b'], insert: [FakeTailMessage(101)]);

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
            expect(strategy.positionOf('a'), 101);
            expect(strategy.positionOf('b'), 102);
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
            strategy.fail('a');

            strategy.incoming([FakeTailMessage(102), FakeTailMessage(101)]);

            expect(strategy.tip, 102);
            expectTail(['b', 'a']);
          });

          test('a publishing row is still at tip+1 after an incoming one', () {
            allocate('a');
            allocate('b');
            strategy.publishStart('b');

            strategy.incoming([FakeTailMessage(101)]);

            expect(strategy.positionOf('b'), strategy.tip + 1);
            expectTail(['b', 'a']);
          });
        }
      });
    });
  }
}
