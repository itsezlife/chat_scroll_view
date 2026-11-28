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

/// The system's transfer envelope: the system ending it pauses the jobs
/// inside, and the user's cancel of all from its notification removes them.
void main() {
  late FakeOutboxTransfers transfers;
  late FakeOutgoingTail tail;
  late List<OutgoingCancelled> cancelled;

  ChatOutbox<Note> outboxWith({bool deleteOnSystemInterruption = false}) {
    final outbox = ChatOutbox<Note>(
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
      clientMessageIds: clientMessageIdsFrom(),
      deleteOnSystemInterruption: deleteOnSystemInterruption,
    );
    addTearDown(outbox.dispose);
    return outbox;
  }

  setUp(() {
    transfers = FakeOutboxTransfers();
    tail = FakeOutgoingTail();
    cancelled = [];
  });

  OutgoingMessage sendText(ChatOutbox<Note> outbox, String text) =>
      outbox.sendText('c1', RichText.plain(text), payload: Note(text: text))!;

  OutgoingMessage sendPhoto(ChatOutbox<Note> outbox, String id) => outbox.send(
    'c1',
    PlannedSend.single(photo(id), form: SendForm.media),
    payload: Note(text: id),
  )!;

  PublishJobId jobOf(String clientMessageId) => transfers.jobs
      .singleWhere((job) => job.tag == 'chat:c1:$clientMessageId')
      .id;

  const interrupted = PublishJobState.paused(PauseReason.systemInterrupted);

  group('the system ends the envelope', () {
    test('by default the message keeps sending in its stage and goes on '
        'once the job resumes', () async {
      final diagnostics = RecordingDiagnostics.install();
      final outbox = outboxWith();
      sendPhoto(outbox, 'a');
      await pumpEventQueue();
      final job = jobOf('cm1');
      transfers.setState(job, const PublishJobState.uploading());
      await pumpEventQueue();

      transfers.setState(job, interrupted);
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.uploading(),
      );
      expect(transfers.cancelled, isEmpty);
      expect(tail.provisional, ['cm1']);
      expect(diagnostics.whereOp(OutboxOp.systemInterrupted), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: job,
          ),
          fields: {'action': 'kept'},
        ),
      ]);

      transfers.setState(job, const PublishJobState.uploading());
      await pumpEventQueue();

      expect(diagnostics.whereOp(OutboxOp.resumed), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: job,
          ),
          fields: {'stage': 'upload'},
        ),
      ]);

      transfers.setState(job, const PublishJobState.completed(null));
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.sent(),
      );
      expect(diagnostics.whereOp(OutboxOp.resumed), hasLength(1));
    });

    test('with deleteOnSystemInterruption the job is cancelled and the '
        'message deleted; every message the end paused leaves in one '
        'rebaseTail', () async {
      final diagnostics = RecordingDiagnostics.install();
      final outbox = outboxWith(deleteOnSystemInterruption: true);
      sendPhoto(outbox, 'a');
      sendPhoto(outbox, 'b');
      sendText(outbox, 'stays');
      await pumpEventQueue();
      final (a, b) = (jobOf('cm1'), jobOf('cm2'));
      final rebasesBefore = tail.rebases.length;

      transfers
        ..setState(a, interrupted)
        ..setState(b, interrupted);
      await pumpEventQueue();

      expect(transfers.cancelled, [a, b]);
      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      expect(outbox.byClientMessageId('c1', 'cm2'), isNull);
      expect(tail.provisional, ['cm3']);
      expect(tail.rebases.length - rebasesBefore, 1);
      expect(
        [for (final c in cancelled) (c.message.clientMessageId, c.rowRemoved)],
        [('cm1', true), ('cm2', true)],
      );
      expect(
        diagnostics.whereOp(OutboxOp.systemInterrupted).map((e) => e.fields),
        everyElement({'action': 'deleted'}),
      );
      expect(diagnostics.whereOp(OutboxOp.cancelled), [
        for (final (id, job) in [('cm1', a), ('cm2', b)])
          isChatEvent(
            level: ChatEventLevel.info,
            correlation: ChatCorrelation(
              chatId: 'c1',
              clientMessageId: id,
              jobId: job,
            ),
            fields: {'trigger': 'systemInterruption', 'stage': 'upload'},
          ),
      ]);
      expect(diagnostics.whereOp(OutboxOp.envelopeCancelAll), isEmpty);
    });

    test('a job paused by the user is not a system interruption', () async {
      final diagnostics = RecordingDiagnostics.install();
      final outbox = outboxWith(deleteOnSystemInterruption: true);
      sendPhoto(outbox, 'a');
      await pumpEventQueue();

      transfers.setState(
        jobOf('cm1'),
        const PublishJobState.paused(PauseReason.user),
      );
      await pumpEventQueue();

      expect(outbox.byClientMessageId('c1', 'cm1'), isNotNull);
      expect(transfers.cancelled, isEmpty);
      expect(diagnostics.whereOp(OutboxOp.systemInterrupted), isEmpty);
    });
  });

  group('the user cancels all from the notification', () {
    test('every outgoing message of the envelope is deleted, the rows '
        'Absent in one rebaseTail', () async {
      final diagnostics = RecordingDiagnostics.install();
      final outbox = outboxWith();
      sendPhoto(outbox, 'a');
      sendText(outbox, 'two');
      sendPhoto(outbox, 'c');
      await pumpEventQueue();
      final (a, c) = (jobOf('cm1'), jobOf('cm3'));
      final rebasesBefore = tail.rebases.length;

      // The engine cancels every job of the envelope, one snapshot each.
      transfers
        ..remove(a)
        ..remove(c);
      await pumpEventQueue();

      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      expect(outbox.byClientMessageId('c1', 'cm3'), isNull);
      expect(outbox.byClientMessageId('c1', 'cm2'), isNotNull);
      expect(tail.provisional, ['cm2']);
      expect(tail.rebases.length - rebasesBefore, 1);
      // The owner did not cancel them: the engine had.
      expect(transfers.cancelled, isEmpty);
      expect(
        [for (final c in cancelled) c.message.clientMessageId],
        ['cm1', 'cm3'],
      );
      expect(outbox.debugSnapshot('c1').counters.cancels, 2);
      expect(
        diagnostics.whereOp(OutboxOp.cancelled).map((e) => e.fields),
        everyElement({'trigger': 'notificationCancelAll', 'stage': 'prepare'}),
      );
      expect(diagnostics.whereOp(OutboxOp.envelopeCancelAll), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: const ChatCorrelation(chatId: 'c1'),
          fields: {'deleted': 2, 'pending': 0},
        ),
      ]);
    });

    test(
      "a job removed by the outbox's own cancel is not a cancel of all",
      () async {
        final diagnostics = RecordingDiagnostics.install();
        final outbox = outboxWith();
        sendPhoto(outbox, 'a');
        await pumpEventQueue();

        outbox.cancel('c1', 'cm1');
        await pumpEventQueue();

        expect(cancelled, hasLength(1));
        expect(outbox.debugSnapshot('c1').counters.cancels, 1);
        expect(diagnostics.whereOp(OutboxOp.cancelled).map((e) => e.fields), [
          {'trigger': 'menu', 'stage': 'prepare'},
        ]);
        expect(diagnostics.whereOp(OutboxOp.envelopeCancelAll), isEmpty);
      },
    );

    test('a sent message stays sent when its job leaves', () async {
      final outbox = outboxWith();
      sendText(outbox, 'one');
      await pumpEventQueue();
      final job = jobOf('cm1');
      transfers.setState(job, const PublishJobState.completed(null));
      await pumpEventQueue();

      transfers.remove(job);
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.sent(),
      );
      expect(cancelled, isEmpty);
    });

    test('a message whose server answer is in flight waits for it: an '
        'accept keeps it sent, any other answer deletes it', () async {
      final diagnostics = RecordingDiagnostics.install();
      final outbox = outboxWith();
      final sender = RecordingOutgoingSender<Note>();
      final accept = Completer<OutgoingSendAnswer<Note>>();
      final reject = Completer<OutgoingSendAnswer<Note>>();
      sender
        ..answerBy((_) => accept.future)
        ..answerBy((_) => reject.future);
      outbox.registerSender(sender);
      sendText(outbox, 'one');
      await pumpEventQueue();
      sendText(outbox, 'two');
      await pumpEventQueue();
      expect(sender.requests, hasLength(2));

      transfers
        ..remove(jobOf('cm1'))
        ..remove(jobOf('cm2'));
      await pumpEventQueue();

      expect(diagnostics.whereOp(OutboxOp.envelopeCancelAll), [
        isChatEvent(fields: {'deleted': 0, 'pending': 2}),
      ]);
      accept.complete(const OutgoingSendAnswer.sent(serverMessageId: 101));
      reject.complete(
        const OutgoingSendAnswer.rejected('spam', retryable: true),
      );
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.sent(),
      );
      expect(outbox.byClientMessageId('c1', 'cm2'), isNull);
      expect([for (final c in cancelled) c.message.clientMessageId], ['cm2']);
    });
  });

  test('after a force quit the journal resumes: a seeded job reads as '
      'sending and publishes once the sender is registered', () async {
    final outbox = outboxWith();
    transfers.seed(
      PublishRequest(
        tag: ChatOutbox.tagOf('c1', 'a'),
        items: const [],
        payload: const NotePayloadCodec().encode(const Note(text: 'hello')),
        publisher: ChatOutbox.publisherId,
        idempotencyKey: 'a',
        orderingGroup: 'c1',
      ),
      state: const PublishJobState.awaitingPublisher(),
    );

    final [pending] = await outbox.pendingFor('c1');
    expect(pending.status, const OutgoingStatus.publishing());

    outbox.registerSender(RecordingOutgoingSender<Note>());
    await pumpEventQueue();

    expect(
      outbox.byClientMessageId('c1', 'a')?.status,
      const OutgoingStatus.sent(),
    );
    expect(cancelled, isEmpty);
  });
}
