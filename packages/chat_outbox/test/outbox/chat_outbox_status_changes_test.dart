import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

import '../support/note_payload_codec.dart';
import '../support/sends.dart';

void main() {
  late FakeOutboxTransfers transfers;
  late ChatOutbox<Note> outbox;
  late List<(String, OutgoingStatus)> heard;

  setUp(() {
    transfers = FakeOutboxTransfers();
    heard = [];
    outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: (chatId) =>
          SequentialServerIds(chatId: chatId, tail: FakeOutgoingTail()),
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      clientMessageIds: clientMessageIdsFrom(),
      onStatusChanged: (message) =>
          heard.add((message.clientMessageId, message.status)),
    );
    addTearDown(outbox.dispose);
  });

  OutgoingMessage sendText(String text) =>
      outbox.sendText('c1', RichText.plain(text), payload: Note(text: text))!;

  PublishJobId jobOf(String clientMessageId) => transfers.jobs
      .singleWhere((job) => job.tag == 'chat:c1:$clientMessageId')
      .id;

  Future<void> fail(String clientMessageId) async {
    transfers.setState(
      jobOf(clientMessageId),
      const PublishJobState.failed(
        stage: PublishStage.publish,
        reason: PublishFailureReason('network'),
        retryable: true,
      ),
    );
    await pumpEventQueue();
  }

  test('hears each change of a message status as its job moves, once per '
      'change', () async {
    sendText('one');
    await pumpEventQueue();
    expect(heard, isEmpty, reason: 'the send itself is not a change');

    transfers.setState(jobOf('cm1'), const PublishJobState.publishing());
    await pumpEventQueue();
    transfers.setState(jobOf('cm1'), const PublishJobState.publishing());
    await pumpEventQueue();
    transfers.setState(jobOf('cm1'), const PublishJobState.completed(null));
    await pumpEventQueue();

    expect(heard, [
      ('cm1', const OutgoingStatus.sent()),
    ], reason: 'a text starts publishing, so publishing again is no change');
  });

  test('hears a failure, and the stage a retry repeats', () async {
    sendText('one');
    await pumpEventQueue();

    await fail('cm1');
    outbox.retry('c1', 'cm1');

    expect(heard, [
      ('cm1', const OutgoingStatus.failed(OutgoingFailure.network())),
      ('cm1', const OutgoingStatus.publishing()),
    ]);
  });

  test('hears nothing of a cancel, which onCancelled reports', () async {
    sendText('one');
    await pumpEventQueue();

    outbox.cancel('c1', 'cm1');
    await pumpEventQueue();

    expect(heard, isEmpty);
  });
}
