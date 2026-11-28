import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
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
  late ChatOutbox<Note> outbox;

  setUp(() {
    transfers = FakeOutboxTransfers();
    tail = FakeOutgoingTail();
    outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: (chatId) => SequentialServerIds(chatId: chatId, tail: tail),
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      undecodableRowOf: (message) =>
          FakeTailMessage(message.position, message.clientMessageId),
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(outbox.dispose);
  });

  OutgoingMessage sendText(String text) =>
      outbox.sendText('c1', RichText.plain(text), payload: Note(text: text))!;

  OutgoingMessage sendPhoto(String id) => outbox.send(
    'c1',
    PlannedSend.single(photo(id), form: SendForm.media),
    payload: const Note(text: ''),
  )!;

  PublishJobId jobOf(String clientMessageId) => transfers.jobs
      .singleWhere((job) => job.tag == 'chat:c1:$clientMessageId')
      .id;

  /// Fails message [clientMessageId]'s job at [stage] for [reason], its
  /// item [itemId] (when given) failed too.
  Future<void> fail(
    String clientMessageId, {
    PublishStage stage = PublishStage.upload,
    String reason = 'network',
    bool retryable = true,
    String? itemId,
  }) async {
    final failed = PublishJobState.failed(
      stage: stage,
      reason: PublishFailureReason(reason),
      retryable: retryable,
    );
    transfers.setState(
      jobOf(clientMessageId),
      failed,
      items: {
        ?itemId: PublishItemState.failed(
          stage: stage,
          reason: PublishFailureReason(reason),
          retryable: retryable,
        ),
      },
    );
    await pumpEventQueue();
  }

  group('a failed message', () {
    test('sinks below every sending row, reported as failed with its '
        'reason, stage and failed items', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      sendText('two');
      await pumpEventQueue();
      expect(tail.provisional, ['cm1', 'cm2']);

      await fail('cm1', itemId: 'item:cm1:0');

      expect(tail.provisional, ['cm2', 'cm1']);
      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.failed(OutgoingFailure.network()),
      );
      expect(diagnostics.whereOp(OutboxOp.failed), [
        isChatEvent(
          level: ChatEventLevel.warning,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: jobOf('cm1'),
          ),
          fields: {'reason': 'network', 'stage': 'upload', 'itemsFailed': 1},
        ),
      ]);
    });

    test('failed rows keep creation order among themselves, below the '
        'sending rows', () async {
      sendPhoto('a');
      sendPhoto('b');
      sendText('three');
      await pumpEventQueue();

      await fail('cm2');
      await fail('cm1');

      expect(tail.provisional, ['cm3', 'cm1', 'cm2']);
    });

    test('a later row that publishes moves to tip+1, the failed rows staying '
        'below it, and proposes tip+1', () async {
      final sender = RecordingOutgoingSender<Note>();
      final answer = Completer<OutgoingSendAnswer<Note>>();
      addTearDown(() {
        if (!answer.isCompleted) {
          answer.complete(OutgoingSendAnswer.rejected('x'));
        }
      });
      sender.answerBy((_) => answer.future);
      outbox.registerSender(sender);
      sendPhoto('a');
      sendPhoto('b');
      await pumpEventQueue();
      await fail('cm2');
      sendPhoto('c');
      await pumpEventQueue();
      expect(tail.provisional, ['cm1', 'cm3', 'cm2']);

      transfers.setState(jobOf('cm3'), const PublishJobState.publishing());
      await pumpEventQueue();

      expect(tail.provisional, ['cm3', 'cm1', 'cm2']);
      expect(tail.positionOf('cm3'), 101);
      expect(sender.requests.single.proposedId, 101);
    });

    group('reads its job failure as a closed reason', () {
      final cases = <String, (PublishStage, String, String)>{
        'the network': (PublishStage.upload, 'network', 'network'),
        'a rejection': (PublishStage.publish, 'chatClosed', 'rejected'),
        'a server denial': (
          PublishStage.publish,
          'chat.denied:${CapabilityAction.sendPhoto.name}',
          'denied',
        ),
        'a lost source': (PublishStage.upload, 'sourceLost', 'sourceLost'),
        'too large': (PublishStage.prepare, 'tooLarge', 'tooLarge'),
        "the engine's own fault": (
          PublishStage.publish,
          PublishFailureReason.publisherError,
          'unknown',
        ),
      };
      for (final MapEntry(key: name, value: (stage, code, reason))
          in cases.entries) {
        test(name, () async {
          final diagnostics = RecordingDiagnostics.install();
          sendPhoto('a');
          await pumpEventQueue();

          await fail('cm1', stage: stage, reason: code);

          expect(outbox.byClientMessageId('c1', 'cm1')?.status.name, 'failed');
          final event = diagnostics.whereOp(OutboxOp.failed).single;
          expect(event.fields['reason'], reason);
          expect(event.fields['stage'], stage.name);
          // A rejection's code is the server's: never in an event.
          expect('${event.fields}', isNot(contains('chatClosed')));
        });
      }
    });
  });

  group('retry', () {
    test('after an upload failure repeats the upload only, keeping the '
        'journaled parts, and moves the row after the sending rows', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      sendPhoto('b');
      sendText('three');
      await pumpEventQueue();
      await fail('cm1', itemId: 'item:cm1:0');
      await fail('cm2', itemId: 'item:cm2:0');
      expect(tail.provisional, ['cm3', 'cm1', 'cm2']);

      expect(outbox.retry('c1', 'cm2'), OutgoingRetryOutcome.retried);
      await pumpEventQueue();

      expect(transfers.retried, [jobOf('cm2')]);
      // The same job: nothing is sent again from the start.
      expect(transfers.requests, hasLength(3));
      expect(tail.provisional, ['cm3', 'cm2', 'cm1']);
      expect(
        outbox.byClientMessageId('c1', 'cm2')?.status,
        const OutgoingStatus.uploading(),
      );
      expect(outbox.debugSnapshot('c1').counters.retries, 1);
      expect(diagnostics.whereOp(OutboxOp.retried), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm2',
            jobId: jobOf('cm2'),
          ),
          fields: {'stage': 'upload', 'uploadsKept': true, 'newSources': 0},
        ),
      ]);
      expect(
        diagnostics
            .whereOp(OutboxOp.tailRebased)
            .where((event) => event.fields['reason'] == 'retry'),
        isNotEmpty,
      );
    });

    test('after a publish failure calls publish only, with the same client '
        'message id', () async {
      final diagnostics = RecordingDiagnostics.install();
      final sender = RecordingOutgoingSender<Note>()
        ..answerWith(OutgoingSendAnswer.rejected('busy', retryable: true));
      outbox.registerSender(sender);
      sendPhoto('remote-a');
      await pumpEventQueue();
      expect(outbox.byClientMessageId('c1', 'cm1')?.status.name, 'failed');

      expect(outbox.retry('c1', 'cm1'), OutgoingRetryOutcome.retried);
      await pumpEventQueue();

      expect(sender.requests, hasLength(2));
      expect(sender.requests.last.clientMessageId, 'cm1');
      expect(transfers.requests, hasLength(1));
      expect(transfers.attemptsOf(jobOf('cm1')), 2);
      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.sent(),
      );
      expect(
        diagnostics.whereOp(OutboxOp.retried).single.fields['stage'],
        'publish',
      );
    });

    test('a burst of ten retries applies once; the others are dropped by '
        'the input guard, until the message fails again', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      await pumpEventQueue();
      await fail('cm1');

      final outcomes = [for (var i = 0; i < 10; i++) outbox.retry('c1', 'cm1')];
      await pumpEventQueue();

      expect(outcomes.first, OutgoingRetryOutcome.retried);
      expect(outcomes.skip(1), everyElement(OutgoingRetryOutcome.dropped));
      expect(transfers.retried, hasLength(1));
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
          fields: {'action': 'retry', 'msSinceAccepted': isA<int>()},
        ),
      );

      await fail('cm1');
      expect(outbox.retry('c1', 'cm1'), OutgoingRetryOutcome.retried);
      expect(transfers.retried, hasLength(2));
    });

    test(
      'of a denied message publishes again, as the mobile Retry does',
      () async {
        final sender = RecordingOutgoingSender<Note>()
          ..answerWith(
            const OutgoingSendAnswer.denied(
              CapabilityAction.sendPhoto,
              DenialReason.restricted(),
            ),
          );
        outbox.registerSender(sender);
        sendPhoto('remote-a');
        await pumpEventQueue();
        expect(
          outbox.byClientMessageId('c1', 'cm1')?.status,
          const OutgoingStatus.failed(
            OutgoingFailure.denied(CapabilityAction.sendPhoto),
          ),
        );

        expect(outbox.retry('c1', 'cm1'), OutgoingRetryOutcome.retried);
        await pumpEventQueue();

        expect(sender.requests, hasLength(2));
      },
    );

    test('after a lost source uploads the item from the source the host '
        'gives again', () async {
      final diagnostics = RecordingDiagnostics.install();
      final message = sendPhoto('a');
      await pumpEventQueue();
      await fail('cm1', reason: 'sourceLost', itemId: 'item:cm1:0');
      final source = SourceBytes.memory(Uint8List.fromList([1, 2]));

      expect(
        outbox.retry('c1', 'cm1', sources: {message.items.single.id: source}),
        OutgoingRetryOutcome.retried,
      );

      expect(transfers.retriedItems, [(jobOf('cm1'), 'item:cm1:0', source)]);
      expect(diagnostics.whereOp(OutboxOp.retried).single.fields, {
        'stage': 'upload',
        'uploadsKept': false,
        'newSources': 1,
      });
    });

    test(
      'answers notFailed for a message on its way and unknown for none',
      () async {
        sendPhoto('a');
        await pumpEventQueue();

        expect(outbox.retry('c1', 'cm1'), OutgoingRetryOutcome.notFailed);
        expect(outbox.retry('c1', 'nope'), OutgoingRetryOutcome.unknown);
        expect(transfers.retried, isEmpty);
      },
    );

    test('of a message whose payload did not decode does nothing: only '
        'Delete helps it', () async {
      transfers.seed(
        PublishRequest(
          tag: ChatOutbox.tagOf('c1', 'old'),
          items: const [],
          payload: Uint8List.fromList(utf8.encode('not json')),
          publisher: ChatOutbox.publisherId,
          idempotencyKey: 'old',
          orderingGroup: 'c1',
        ),
        state: const PublishJobState.publishing(),
      );
      await outbox.pendingFor('c1');

      expect(outbox.retry('c1', 'old'), OutgoingRetryOutcome.undecodable);
      expect(transfers.retried, isEmpty);
    });
  });

  group('delete', () {
    test('of a failed message cancels its job; the row leaves the tail and '
        'the message is Absent', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      sendText('two');
      await pumpEventQueue();
      await fail('cm1');
      final job = jobOf('cm1');
      expect(tail.provisional, ['cm2', 'cm1']);

      expect(outbox.delete('c1', 'cm1'), OutgoingCancelOutcome.cancelled);

      expect(transfers.cancelled, [job]);
      expect(outbox.byClientMessageId('c1', 'cm1'), isNull);
      expect(tail.provisional, ['cm2']);
      final correlation = ChatCorrelation(
        chatId: 'c1',
        clientMessageId: 'cm1',
        jobId: job,
      );
      expect(diagnostics.whereOp(OutboxOp.cancelled), [
        isChatEvent(
          correlation: correlation,
          fields: {'trigger': 'delete', 'stage': 'failed'},
        ),
      ]);
      expect(diagnostics.whereOp(OutboxOp.deleted), [
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: correlation,
          fields: {'status': 'failed'},
        ),
      ]);
    });

    test('a burst of ten deletes applies once; the others are dropped by '
        'the input guard', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendPhoto('a');
      await pumpEventQueue();
      await fail('cm1');

      final outcomes = [
        for (var i = 0; i < 10; i++) outbox.delete('c1', 'cm1'),
      ];

      expect(outcomes.first, OutgoingCancelOutcome.cancelled);
      expect(outcomes.skip(1), everyElement(OutgoingCancelOutcome.dropped));
      expect(transfers.cancelled, hasLength(1));
      expect(diagnostics.whereOp(OutboxOp.deleted), hasLength(1));
      final drops = diagnostics.whereOp(OutboxOp.actionDropped);
      expect(drops, hasLength(9));
      expect(drops.first.fields['action'], 'delete');
    });

    test('helps a message whose payload did not decode', () async {
      final job = transfers.seed(
        PublishRequest(
          tag: ChatOutbox.tagOf('c1', 'old'),
          items: const [],
          payload: Uint8List.fromList(utf8.encode('not json')),
          publisher: ChatOutbox.publisherId,
          idempotencyKey: 'old',
          orderingGroup: 'c1',
        ),
        state: const PublishJobState.publishing(),
      );
      await outbox.pendingFor('c1');

      expect(outbox.delete('c1', 'old'), OutgoingCancelOutcome.cancelled);

      expect(transfers.cancelled, [job]);
      expect(tail.provisional, isEmpty);
    });

    test('of a sent message is too late: it stays sent', () async {
      outbox.registerSender(RecordingOutgoingSender<Note>());
      sendText('one');
      await pumpEventQueue();

      expect(outbox.delete('c1', 'cm1'), OutgoingCancelOutcome.tooLate);
      expect(transfers.cancelled, isEmpty);
    });
  });
}
