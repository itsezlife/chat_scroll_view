import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

import '../support/note_payload_codec.dart';
import '../support/sends.dart';

void main() {
  late FakeOutboxTransfers transfers;
  late FakeOutgoingTail tail;
  late RecordingOutgoingSender<Note> sender;
  late List<OutgoingCancelled> cancelled;
  late List<OutgoingItemDropped> dropped;
  late ChatOutbox<Note> outbox;

  setUp(() {
    transfers = FakeOutboxTransfers();
    tail = FakeOutgoingTail();
    sender = RecordingOutgoingSender();
    cancelled = [];
    dropped = [];
    outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: (chatId) => SequentialServerIds(chatId: chatId, tail: tail),
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      onSent: (sent) {
        if (sent.rowAt case final rowAt?) tail.update(FakeTailMessage(rowAt));
      },
      onCancelled: cancelled.add,
      onItemDropped: dropped.add,
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(outbox.dispose);
  });

  OutgoingMessage sendText(String text) =>
      outbox.sendText('c1', RichText.plain(text), payload: Note(text: text))!;

  OutgoingMessage sendPhoto(String id, {String? caption}) => outbox.send(
    'c1',
    PlannedSend.single(
      photo(id),
      form: SendForm.media,
      caption: switch (caption) {
        final caption? => RichText.plain(caption),
        null => null,
      },
    ),
    payload: Note(text: caption ?? ''),
  )!;

  OutgoingMessage sendAlbum(List<String> ids, {String? caption}) => outbox.send(
    'c1',
    PlannedSend.group(
      [for (final id in ids) photo(id)],
      form: SendForm.media,
      captionIndex: caption == null ? null : 0,
      caption: switch (caption) {
        final caption? => RichText.plain(caption),
        null => null,
      },
    ),
    payload: Note(text: caption ?? ''),
  )!;

  PublishJobId jobOf(String clientMessageId) => transfers.jobs
      .singleWhere((job) => job.tag == 'chat:c1:$clientMessageId')
      .id;

  group('cancel the message', () {
    test('cancels the job; the row leaves the tail and the message is '
        'Absent, reported as cancelled from the menu', () async {
      final diagnostics = RecordingDiagnostics.install();
      final one = sendPhoto('a');
      sendText('two');
      await pumpEventQueue();
      final job = jobOf('cm1');

      expect(outbox.cancel('c1', 'cm1'), OutgoingCancelOutcome.cancelled);

      expect(transfers.cancelled, [job]);
      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      // The next row took the cancelled row's position.
      expect(tail.provisional, ['cm2']);
      expect(tail.positionOf('cm2'), 101);
      expect(cancelled.single.message.clientMessageId, 'cm1');
      expect(cancelled.single.message.status, const OutgoingStatus.cancelled());
      expect(cancelled.single.message.position, one.position);
      expect(cancelled.single.rowRemoved, isTrue);
      expect(outbox.debugSnapshot('c1').counters.cancels, 1);
      expect(diagnostics.whereOp(OutboxOp.cancelled), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: job,
          ),
          fields: {'trigger': 'menu', 'stage': 'prepare'},
        ),
      ]);
    });

    test('a burst of ten cancels cancels once; the others are dropped by '
        'the input guard', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      await pumpEventQueue();

      final outcomes = [
        for (var i = 0; i < 10; i++) outbox.cancel('c1', 'cm1'),
      ];

      expect(outcomes.first, OutgoingCancelOutcome.cancelled);
      expect(outcomes.skip(1), everyElement(OutgoingCancelOutcome.dropped));
      expect(transfers.cancelled, hasLength(1));
      expect(cancelled, hasLength(1));
      expect(diagnostics.whereOp(OutboxOp.cancelled), hasLength(1));
      final drops = diagnostics.whereOp(OutboxOp.actionDropped);
      expect(drops, hasLength(9));
      expect(
        drops.first,
        isChatEvent(
          level: ChatEventLevel.debug,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
          ),
          fields: {'action': 'cancel', 'msSinceAccepted': isA<int>()},
        ),
      );
    });

    test('a cancelled client message id is never issued again', () async {
      final ids = ['cm1', 'cm1'].iterator;
      final reusing = ChatOutbox<Note>(
        transfers: transfers,
        codec: const NotePayloadCodec(),
        itemOf: sendItemOf,
        idStrategyOf: (chatId) =>
            SequentialServerIds(chatId: chatId, tail: FakeOutgoingTail()),
        rowOf: (message, payload) =>
            FakeTailMessage(message.position, message.clientMessageId),
        clientMessageIds: () => (ids..moveNext()).current,
      );
      addTearDown(reusing.dispose);
      reusing.sendText(
        'c1',
        const RichText.plain('one'),
        payload: const Note(text: 'one'),
      );
      reusing.cancel('c1', 'cm1');

      expect(
        () => reusing.sendText(
          'c1',
          const RichText.plain('two'),
          payload: const Note(text: 'two'),
        ),
        throwsStateError,
      );
    });

    test('the next message takes a cancelled row\'s position', () async {
      sendText('one');
      outbox.cancel('c1', 'cm1');

      final two = sendText('two');

      expect(two.position, 101);
      expect(tail.provisional, ['cm2']);
    });
  });

  group('cancel an item', () {
    test('the cross on one album item drops it and the rest publish', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum(['a', 'b']);
      await pumpEventQueue();
      final job = jobOf('cm1');

      expect(
        outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:1')),
        OutgoingCancelOutcome.itemDropped,
      );

      expect(transfers.removedItems, [(job, 'item:cm1:1')]);
      expect(
        [
          for (final item in outbox.byClientMessageId('c1', 'cm1')!.items)
            '${item.id}',
        ],
        ['item:cm1:0'],
      );
      expect('${dropped.single.item.id}', 'item:cm1:1');
      expect(dropped.single.index, 1);
      expect(dropped.single.message.items, hasLength(1));
      expect(cancelled, isEmpty);
      expect(diagnostics.whereOp(OutboxOp.itemDropped), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: job,
            mediaItemId: 'item:cm1:1',
            mediaKey: mediaKeyOf('b').encoded,
          ),
          fields: {
            'index': 1,
            'itemsLeft': 1,
            'hasText': false,
            'trigger': 'cross',
          },
        ),
      ]);
      expect(outbox.debugSnapshot('c1').counters.itemsDropped, 1);

      outbox.registerSender(sender);
      transfers.setState(job, const PublishJobState.publishing());
      await pumpEventQueue();

      expect(
        [for (final id in sender.requests.single.items.keys) '$id'],
        ['item:cm1:0'],
      );
      expect(
        outbox.byClientMessageId('c1', 'cm1')!.status,
        const OutgoingStatus.sent(),
      );
    });

    test(
      'the cross on the only item with no text cancels the message',
      () async {
        final diagnostics = RecordingDiagnostics.install();
        sendPhoto('a');
        await pumpEventQueue();
        final job = jobOf('cm1');

        expect(
          outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:0')),
          OutgoingCancelOutcome.cancelled,
        );

        expect(transfers.cancelled, [job]);
        expect(transfers.removedItems, isEmpty);
        expect(dropped, isEmpty);
        expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
        expect(tail.provisional, isEmpty);
        expect(
          diagnostics.whereOp(OutboxOp.cancelled).single.fields['trigger'],
          'onlyItem',
        );
      },
    );

    test('the last item of an album cancelled with no text deletes the '
        'message', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum(['a', 'b']);
      await pumpEventQueue();
      final job = jobOf('cm1');

      outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:0'));
      final last = outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:1'));

      expect(last, OutgoingCancelOutcome.cancelled);
      expect(transfers.cancelled, [job]);
      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      expect(cancelled.single.message.clientMessageId, 'cm1');
      expect(
        diagnostics.whereOp(OutboxOp.cancelled).single.fields['trigger'],
        'lastItemNoText',
      );
    });

    test('the last item cancelled with text publishes the text alone, after '
        'the other sending messages', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a', caption: 'look');
      sendText('two');
      await pumpEventQueue();
      final job = jobOf('cm1');
      expect(tail.provisional, ['cm1', 'cm2']);

      expect(
        outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:0')),
        OutgoingCancelOutcome.itemDropped,
      );

      expect(transfers.committed, [job]);
      expect(transfers.cancelled, isEmpty);
      expect(outbox.byClientMessageId('c1', 'cm1')!.items, isEmpty);
      // The job joined the end of its ordering group: so does its row.
      expect(tail.provisional, ['cm2', 'cm1']);
      expect(diagnostics.whereOp(OutboxOp.awaitingOwner), [
        isChatEvent(
          level: ChatEventLevel.warning,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: job,
          ),
          fields: {'itemsLeft': 0, 'hasText': true, 'action': 'commit'},
        ),
      ]);

      outbox.registerSender(sender);
      await pumpEventQueue();

      final request = sender.requests.singleWhere(
        (request) => request.clientMessageId == 'cm1',
      );
      expect(request.items, isEmpty);
      expect(
        outbox.byClientMessageId('c1', 'cm1')!.status,
        const OutgoingStatus.sent(),
      );
    });

    test('a repeated cross on one item is dropped', () async {
      sendAlbum(['a', 'b', 'c']);
      await pumpEventQueue();

      final outcomes = [
        for (var i = 0; i < 10; i++)
          outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:1')),
      ];

      expect(outcomes.first, OutgoingCancelOutcome.itemDropped);
      expect(outcomes.skip(1), everyElement(OutgoingCancelOutcome.dropped));
      expect(transfers.removedItems, hasLength(1));
    });
  });

  group('the status control', () {
    test(
      'a cell\'s cancel of one album item\'s upload drops only that item',
      () async {
        final diagnostics = RecordingDiagnostics.install();
        sendAlbum(['a', 'b']);
        await pumpEventQueue();
        final job = jobOf('cm1');

        transfers.cancelUpload(job, 'item:cm1:0');
        await pumpEventQueue();

        expect(transfers.removedItems, isEmpty);
        expect(
          [
            for (final item in outbox.byClientMessageId('c1', 'cm1')!.items)
              '${item.id}',
          ],
          ['item:cm1:1'],
        );
        expect('${dropped.single.item.id}', 'item:cm1:0');
        expect(cancelled, isEmpty);
        expect(diagnostics.whereOp(OutboxOp.itemDropped).single.fields, {
          'index': 0,
          'itemsLeft': 1,
          'hasText': false,
          'trigger': 'statusControl',
        });
      },
    );

    test('a cell\'s cancel of the only item with no text leaves the job '
        'awaiting its owner, and the outbox cancels it', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      sendText('two');
      await pumpEventQueue();
      final job = jobOf('cm1');

      transfers.cancelUpload(job, 'item:cm1:0');
      await pumpEventQueue();

      expect(transfers.cancelled, [job]);
      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      expect(tail.provisional, ['cm2']);
      expect(dropped, isEmpty);
      expect(cancelled.single.message.clientMessageId, 'cm1');
      expect(diagnostics.whereOp(OutboxOp.awaitingOwner).single.fields, {
        'itemsLeft': 0,
        'hasText': false,
        'action': 'cancel',
      });
      expect(diagnostics.whereOp(OutboxOp.cancelled).single.fields, {
        'trigger': 'statusControl',
        'stage': 'prepare',
      });
    });

    test(
      'a cell\'s cancel of the only item with text publishes the text',
      () async {
        sendPhoto('a', caption: 'look');
        await pumpEventQueue();
        final job = jobOf('cm1');

        transfers.cancelUpload(job, 'item:cm1:0');
        await pumpEventQueue();

        expect(transfers.committed, [job]);
        expect(transfers.cancelled, isEmpty);
        expect('${dropped.single.item.id}', 'item:cm1:0');
        expect(outbox.byClientMessageId('c1', 'cm1')!.items, isEmpty);
      },
    );
  });

  group('a late cancel', () {
    test('a cancel racing a publish the server accepts is too late: the '
        'message stays sent', () async {
      final diagnostics = RecordingDiagnostics.install();
      final answer = Completer<OutgoingSendAnswer<Note>>();
      sender.answerBy((_) => answer.future);
      outbox.registerSender(sender);
      sendText('one');
      await pumpEventQueue();
      expect(sender.requests, hasLength(1));

      expect(outbox.cancel('c1', 'cm1'), OutgoingCancelOutcome.pending);
      expect(outbox.cancel('c1', 'cm1'), OutgoingCancelOutcome.dropped);
      answer.complete(const OutgoingSendAnswer.sent(serverMessageId: 101));
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'cm1')!.status,
        const OutgoingStatus.sent(),
      );
      expect(transfers.cancelled, isEmpty);
      expect(cancelled, isEmpty);
      expect(diagnostics.whereOp(OutboxOp.cancelled), isEmpty);
      expect(diagnostics.whereOp(OutboxOp.cancelTooLate).single.fields, {
        'stage': 'publish',
      });
      expect(outbox.debugSnapshot('c1').counters.cancelsTooLate, 1);
    });

    test('a cancel waiting for an answer that is not an accept cancels the '
        'message then', () async {
      final answer = Completer<OutgoingSendAnswer<Note>>();
      sender.answerBy((_) => answer.future);
      outbox.registerSender(sender);
      sendText('one');
      await pumpEventQueue();
      final job = jobOf('cm1');

      expect(outbox.cancel('c1', 'cm1'), OutgoingCancelOutcome.pending);
      expect(cancelled, isEmpty);
      answer.complete(OutgoingSendAnswer.rejected('spam', retryable: true));
      await pumpEventQueue();

      expect(transfers.cancelled, [job]);
      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      expect(cancelled.single.message.clientMessageId, 'cm1');
      expect(tail.provisional, isEmpty);
    });

    test('a cancel of a sent message is too late', () async {
      final diagnostics = RecordingDiagnostics.install();
      outbox.registerSender(sender);
      sendText('one');
      await pumpEventQueue();

      expect(outbox.cancel('c1', 'cm1'), OutgoingCancelOutcome.tooLate);

      expect(
        outbox.byClientMessageId('c1', 'cm1')!.status,
        const OutgoingStatus.sent(),
      );
      expect(diagnostics.whereOp(OutboxOp.cancelTooLate).single.fields, {
        'stage': 'sent',
      });
    });

    test('while the publish is in flight an item still drops', () async {
      final answer = Completer<OutgoingSendAnswer<Note>>();
      sender.answerBy((_) => answer.future);
      outbox.registerSender(sender);
      sendAlbum(['remote-a', 'remote-b']);
      await pumpEventQueue();
      expect(sender.requests, hasLength(1));

      expect(
        outbox.cancelItem('c1', 'cm1', const MediaItemId('cm1:1')),
        OutgoingCancelOutcome.itemDropped,
      );
      answer.complete(const OutgoingSendAnswer.sent(serverMessageId: 101));
      await pumpEventQueue();

      final message = outbox.byClientMessageId('c1', 'cm1')!;
      expect(message.status, const OutgoingStatus.sent());
      expect([for (final item in message.items) '${item.id}'], ['item:cm1:0']);
    });
  });

  test('cancelling a failed message cancels its job', () async {
    final diagnostics = RecordingDiagnostics.install();
    sendPhoto('a');
    await pumpEventQueue();
    final job = jobOf('cm1');
    transfers.setState(
      job,
      const PublishJobState.failed(
        stage: PublishStage.upload,
        reason: PublishFailureReason('network'),
        retryable: true,
      ),
    );
    await pumpEventQueue();

    expect(outbox.cancel('c1', 'cm1'), OutgoingCancelOutcome.cancelled);

    expect(transfers.cancelled, [job]);
    expect(diagnostics.whereOp(OutboxOp.cancelled).single.fields, {
      'trigger': 'menu',
      'stage': 'failed',
    });
  });
}
