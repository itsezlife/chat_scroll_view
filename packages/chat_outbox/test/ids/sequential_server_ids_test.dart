import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OutgoingIdStrategyContract.run(
    (tail) => SequentialServerIds(chatId: 'c1', tail: tail),
  );

  late FakeOutgoingTail tail;
  late SequentialServerIds strategy;

  setUp(() {
    tail = FakeOutgoingTail();
    strategy = SequentialServerIds(chatId: 'c1', tail: tail);
  });

  void allocate(String id, {bool failed = false, bool restored = false}) =>
      strategy.allocate(
        id,
        (position) => FakeTailMessage(position, id),
        failed: failed,
        restored: restored,
      );

  test('is named sequentialServerIds', () {
    expect(strategy.name, 'sequentialServerIds');
  });

  group('proposedId', () {
    test('is tip+1, the publishing row\'s position', () {
      allocate('a');
      allocate('b');
      strategy.publishStart('b');

      expect(strategy.proposedId, 101);
      expect(strategy.positionOf('b'), strategy.proposedId);
    });

    test('is read at publish time: tip+1 after an incoming message', () {
      allocate('a');
      final atCreation = strategy.proposedId;

      strategy
        ..incoming([FakeTailMessage(101)])
        ..publishStart('a');

      expect(atCreation, 101);
      expect(strategy.proposedId, 102);
      expect(strategy.positionOf('a'), 102);
    });

    test('is the accepted id once confirmed', () {
      allocate('a');
      allocate('b');
      strategy.publishStart('b');
      final proposed = strategy.proposedId;

      expect(strategy.confirm('b'), proposed);
    });
  });

  group('diagnostics', () {
    test(
      'positionAllocated: offset from the tip, strategy, new or restart',
      () {
        final diagnostics = RecordingDiagnostics.install();

        allocate('a');
        allocate('b', restored: true);

        expect(diagnostics.whereOp(OutboxOp.positionAllocated), [
          isChatEvent(
            level: ChatEventLevel.debug,
            category: ChatEventCategory.outbox,
            correlation: const ChatCorrelation(
              chatId: 'c1',
              clientMessageId: 'a',
              scrollId: '101',
            ),
            fields: {
              'offsetFromTip': 1,
              'strategy': 'sequentialServerIds',
              'allocation': 'new',
            },
          ),
          isChatEvent(
            correlation: const ChatCorrelation(
              chatId: 'c1',
              clientMessageId: 'b',
              scrollId: '102',
            ),
            fields: {
              'offsetFromTip': 2,
              'strategy': 'sequentialServerIds',
              'allocation': 'restart',
            },
          ),
        ]);
      },
    );

    test('positionAllocated reports the position after failed rows sink', () {
      allocate('a');
      strategy.fail('a');
      final diagnostics = RecordingDiagnostics.install();

      allocate('b');

      expect(
        diagnostics.whereOp(OutboxOp.positionAllocated).single.correlation,
        const ChatCorrelation(
          chatId: 'c1',
          clientMessageId: 'b',
          scrollId: '101',
        ),
      );
    });

    test('tailRebased: one event per moved row, then the trigger', () {
      allocate('a');
      allocate('b');
      allocate('c');
      final diagnostics = RecordingDiagnostics.install();

      strategy.publishStart('c');

      expect(diagnostics.whereOp(OutboxOp.tailRebased), [
        for (final (id, from, to) in [
          ('c', 103, 101),
          ('a', 101, 102),
          ('b', 102, 103),
        ])
          isChatEvent(
            level: ChatEventLevel.debug,
            category: ChatEventCategory.outbox,
            correlation: ChatCorrelation(
              chatId: 'c1',
              clientMessageId: id,
              scrollId: '$to',
            ),
            fields: {
              'reason': 'publishStart',
              'rows': 3,
              'inserted': 0,
              'from': from,
            },
          ),
      ]);
    });

    test('tailRebased: an incoming move names every row it moved', () {
      allocate('a');
      allocate('b');
      final diagnostics = RecordingDiagnostics.install();

      strategy.incoming([FakeTailMessage(101)]);

      final events = diagnostics.whereOp(OutboxOp.tailRebased);
      expect(
        [for (final event in events) event.correlation.clientMessageId],
        ['a', 'b', null],
      );
      expect(events.first.fields, {
        'reason': 'incoming',
        'rows': 2,
        'inserted': 1,
        'from': 101,
      });
      expect(events.last.fields, {
        'reason': 'incoming',
        'rows': 2,
        'inserted': 1,
      });
    });

    test('tailRebased: a removed row is the trigger, with no position', () {
      allocate('a');
      allocate('b');
      final diagnostics = RecordingDiagnostics.install();

      strategy.remove('a');

      expect(diagnostics.whereOp(OutboxOp.tailRebased), [
        isChatEvent(
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'b',
            scrollId: '101',
          ),
          fields: {'reason': 'removed', 'rows': 1, 'inserted': 0, 'from': 102},
        ),
        isChatEvent(
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'a',
          ),
          fields: {'reason': 'removed', 'rows': 1, 'inserted': 0},
        ),
      ]);
    });

    test('tailRebased reasons: failedSink, retry, restart', () {
      allocate('a');
      allocate('b');
      allocate('x');
      final diagnostics = RecordingDiagnostics.install();

      strategy
        ..fail('a')
        ..fail('b')
        ..retry('b');
      allocate('c', failed: true);
      allocate('d', restored: true);
      allocate('e');

      expect(
        {
          for (final event in diagnostics.whereOp(OutboxOp.tailRebased))
            event.fields['reason'],
        },
        {'failedSink', 'retry', 'restart'},
      );
    });

    test('carry ids and counts only', () {
      final diagnostics = RecordingDiagnostics.install();
      allocate('a');
      strategy.incoming([FakeTailMessage(101)]);

      for (final event in diagnostics.events) {
        for (final value in event.fields.values) {
          expect(
            value,
            anyOf(isA<num>(), isA<bool>(), isA<String>(), isA<List<String>>()),
          );
        }
      }
    });
  });
}
