import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('incoming above the sending rows', () {
    OutgoingIdStrategyContract.run(
      (tail) => LocalIds(chatId: const ChatId('c1'), tail: tail),
    );
  });

  group('incoming appended', () {
    OutgoingIdStrategyContract.run(
      (tail) => LocalIds(
        chatId: const ChatId('c1'),
        tail: tail,
        appendIncoming: true,
      ),
      appendsIncoming: true,
    );
  });

  late FakeOutgoingTail tail;

  setUp(() => tail = FakeOutgoingTail());

  void allocate(OutgoingIdStrategy strategy, String id) => strategy.allocate(
    ClientMessageId(id),
    (position) => FakeTailMessage(position, id),
  );

  test('is named localIds', () {
    expect(LocalIds(chatId: const ChatId('c1'), tail: tail).name, 'localIds');
  });

  group('nextIncomingId', () {
    test('is tip+1 while rows wait, so the message lands above them', () {
      final strategy = LocalIds(chatId: const ChatId('c1'), tail: tail);
      allocate(strategy, 'a');
      allocate(strategy, 'b');

      expect(strategy.nextIncomingId, 101);
      strategy.incoming([FakeTailMessage(strategy.nextIncomingId)]);

      expect(tail.provisional, ['a', 'b']);
      expect(strategy.positionOf(const ClientMessageId('a')), 102);
      expect(strategy.nextIncomingId, 102);
    });

    test('is the id after the newest row with no rows waiting', () {
      final strategy = LocalIds(chatId: const ChatId('c1'), tail: tail);

      expect(strategy.nextIncomingId, 101);
    });

    test('is the id after the rows with the append flag', () {
      final strategy = LocalIds(
        chatId: const ChatId('c1'),
        tail: tail,
        appendIncoming: true,
      );
      allocate(strategy, 'a');
      allocate(strategy, 'b');

      expect(strategy.nextIncomingId, 103);
    });
  });

  group('appendIncoming', () {
    test('the appended message settles the rows above it', () {
      final diagnostics = RecordingDiagnostics.install();
      final strategy = LocalIds(
        chatId: const ChatId('c1'),
        tail: tail,
        appendIncoming: true,
      );
      allocate(strategy, 'a');
      allocate(strategy, 'b');
      final message = FakeTailMessage(strategy.nextIncomingId);

      expect(strategy.incoming([message]), isFalse);
      tail.insertMessage(message);

      // The confirmed row ends the provisional tail: the rows above it keep
      // their positions and are no longer moved.
      expect(tail.provisional, isEmpty);
      expect(strategy.tail, isEmpty);
      expect(strategy.positionOf(const ClientMessageId('a')), 101);
      strategy
        ..publishStart(const ClientMessageId('b'))
        ..fail(const ClientMessageId('a'));
      expect(tail.rebases, isEmpty);
      expect(strategy.remove(const ClientMessageId('a')), isFalse);
      expect(strategy.positionOf(const ClientMessageId('a')), isNull);
      expect(strategy.confirm(const ClientMessageId('b')), 102);
      expect(
        diagnostics.whereOp(OutboxOp.incomingAppended).single,
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(chatId: 'c1', scrollId: '103'),
          fields: {'appendIncoming': true, 'incoming': 1, 'settled': 2},
        ),
      );
    });

    test('rows placed after the appended message form a new tail', () {
      final strategy = LocalIds(
        chatId: const ChatId('c1'),
        tail: tail,
        appendIncoming: true,
      );
      allocate(strategy, 'a');
      final message = FakeTailMessage(strategy.nextIncomingId);
      strategy.incoming([message]);
      tail.insertMessage(message);

      allocate(strategy, 'b');
      allocate(strategy, 'c');
      strategy.publishStart(const ClientMessageId('c'));

      expect(strategy.tip, 102);
      expect(tail.provisional, ['c', 'b']);
      expect(strategy.positionOf(const ClientMessageId('a')), 101);
    });

    test('with no rows waiting it reports nothing', () {
      final diagnostics = RecordingDiagnostics.install();
      final strategy = LocalIds(
        chatId: const ChatId('c1'),
        tail: tail,
        appendIncoming: true,
      );

      expect(strategy.incoming([FakeTailMessage(101)]), isFalse);

      expect(diagnostics.whereOp(OutboxOp.incomingAppended), isEmpty);
    });
  });
}
