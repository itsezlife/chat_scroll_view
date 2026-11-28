import 'package:attach_model/attach_model.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/note_payload_codec.dart';
import '../support/sends.dart';

void main() {
  late FakeOutgoingTail tail;
  late List<String> strategiesMade;
  late ChatOutbox<Note> outbox;

  setUp(() {
    tail = FakeOutgoingTail();
    strategiesMade = [];
    outbox = ChatOutbox(
      transfers: FakeOutboxTransfers(),
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: (chatId) {
        strategiesMade.add(chatId);
        return SequentialServerIds(chatId: chatId, tail: tail);
      },
      onSent: (_) {},
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(outbox.dispose);
  });

  OutgoingMessage? sendText(String text) => outbox.sendText(
    const ChatId('c1'),
    RichText.plain(text),
    payload: Note(text: text),
  );

  test('an accepted send takes the next tail position and its row', () {
    final first = sendText('one')!;
    final second = sendText('two')!;

    expect(first.position, 101);
    expect(second.position, 102);
    expect(tail.provisional, ['cm1', 'cm2']);
    expect(tail.identityAt(101), 'cm1');
  });

  test('a send that throws takes no position', () {
    final refusing = ChatOutbox<Note>(
      transfers: FakeOutboxTransfers(),
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: (chatId) => SequentialServerIds(chatId: chatId, tail: tail),
      onSent: (_) {},
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      capabilitiesOf: (_) => null,
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(refusing.dispose);

    expect(
      () => refusing.send(
        const ChatId('c1'),
        PlannedSend.single(photo('a'), form: SendForm.media),
        payload: const Note(text: 'x'),
        itemIds: const [],
      ),
      throwsArgumentError,
    );
    expect(tail.inserted, isEmpty);
  });

  test('makes one strategy per chat, on its first send', () {
    expect(strategiesMade, isEmpty);

    sendText('one');
    sendText('two');

    expect(strategiesMade, ['c1']);
    expect(outbox.idStrategy(const ChatId('c1')).tail, ['cm1', 'cm2']);
  });

  test('lookups answer the position the row has now', () {
    sendText('one');
    sendText('two');

    outbox.idStrategy(const ChatId('c1')).incoming([FakeTailMessage(101)]);

    expect(
      outbox
          .byClientMessageId(const ChatId('c1'), const ClientMessageId('cm1'))
          ?.position,
      102,
    );
    expect(
      outbox
          .byClientMessageId(const ChatId('c1'), const ClientMessageId('cm2'))
          ?.position,
      103,
    );
  });

  test('accepted reports the strategy', () {
    final diagnostics = RecordingDiagnostics.install();

    sendText('one');

    expect(
      diagnostics.whereOp(OutboxOp.accepted).single.fields,
      containsPair('strategy', 'sequentialServerIds'),
    );
    expect(
      diagnostics.whereOp(OutboxOp.positionAllocated).single.correlation,
      const ChatCorrelation(
        chatId: 'c1',
        clientMessageId: 'cm1',
        scrollId: '101',
      ),
    );
  });

  test('the snapshot holds the strategy, the tip, positions and rebases', () {
    sendText('one');
    sendText('two');
    outbox.idStrategy(const ChatId('c1'))
      ..incoming([FakeTailMessage(101)])
      ..publishStart(const ClientMessageId('cm2'));

    final snapshot = outbox.debugSnapshot(const ChatId('c1'));

    expect(snapshot.strategy, 'sequentialServerIds');
    expect(snapshot.tip, 101);
    expect(
      [for (final row in snapshot.tail) (row.clientMessageId, row.position)],
      [('cm2', 102), ('cm1', 103)],
    );
    expect(snapshot.counters.rebases, {'incoming': 1, 'publishStart': 1});
  });

  test('the snapshot of a chat with no send yet names no strategy', () {
    expect(outbox.debugSnapshot(const ChatId('c2')).strategy, isNull);
    expect(strategiesMade, isEmpty);
  });
}
