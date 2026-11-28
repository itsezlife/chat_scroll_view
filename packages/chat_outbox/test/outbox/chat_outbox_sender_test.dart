import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
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
  late RecordingCapabilityFeedback feedback;
  late List<OutgoingSent<Note>> sent;
  late ChatOutbox<Note> outbox;

  ChatOutbox<Note> outboxWith(
    OutgoingIdStrategy Function(String chatId) idStrategyOf,
  ) {
    final outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: idStrategyOf,
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      feedback: feedback,
      // The host's duty: the confirmed message replaces the outbox's row.
      onSent: (message) {
        sent.add(message);
        switch (message.rowAt) {
          case final rowAt?:
            tail.update(FakeTailMessage(rowAt));
          // The row left: the host places the message at the server's id,
          // unless the chat holds it there already (a fetch brought it).
          case null
              when message.position < tail.tailStart &&
                  tail.at(message.position) == null:
            tail.place(FakeTailMessage(message.position));
          case null:
            break;
        }
      },
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(outbox.dispose);
    return outbox;
  }

  setUp(() {
    transfers = FakeOutboxTransfers();
    tail = FakeOutgoingTail();
    sender = RecordingOutgoingSender();
    feedback = RecordingCapabilityFeedback();
    sent = [];
    outbox = outboxWith(
      (chatId) => SequentialServerIds(chatId: chatId, tail: tail),
    );
  });

  OutgoingMessage sendText(String text) =>
      outbox.sendText('c1', RichText.plain(text), payload: Note(text: text))!;

  OutgoingStatus statusOf(String clientMessageId) =>
      outbox.byClientMessageId('c1', clientMessageId)!.status;

  PublishJobState jobStateOf(int index) => transfers.jobs[index].state;

  test('jobs wait for the sender, and registering it sends them', () async {
    sendText('one');
    await pumpEventQueue();
    expect(sender.requests, isEmpty);
    expect(outbox.debugSnapshot('c1').publisherRegistered, isFalse);

    outbox.registerSender(sender);
    await pumpEventQueue();

    expect(transfers.publisherOf(ChatOutbox.publisherId), isNotNull);
    expect(outbox.debugSnapshot('c1').publisherRegistered, isTrue);
    final request = sender.requests.single;
    expect(request.chatId, 'c1');
    expect(request.clientMessageId, 'cm1');
    expect(request.payload, const Note(text: 'one'));
    expect(request.proposedId, 101);
    expect(request.attempt, 1);
    expect(request.items, isEmpty);
  });

  test('a published message is sent at its proposal: the host settles its '
      'row and the next message proposes the id after it', () async {
    outbox.registerSender(sender);

    sendText('one');
    sendText('two');
    await pumpEventQueue();

    expect([for (final r in sender.requests) r.proposedId], [101, 102]);
    expect(statusOf('cm1'), const OutgoingStatus.sent());
    expect(statusOf('cm2'), const OutgoingStatus.sent());
    expect(outbox.byClientMessageId('c1', 'cm2')!.position, 102);
    expect(
      [for (final s in sent) (s.clientMessageId, s.position, s.rowAt)],
      [('cm1', 101, 101), ('cm2', 102, 102)],
    );
    expect(tail.identityAt(101), 'confirmed');
    expect(tail.identityAt(102), 'confirmed');
    expect(tail.provisional, isEmpty);
    expect(jobStateOf(0), isA<PublishJobState$Completed>());
  });

  group('an answer accepted at the proposal while the call was out', () {
    late Completer<OutgoingSendAnswer<Note>> answer;

    setUp(() {
      answer = Completer();
      sender.answerBy((_) => answer.future);
      outbox.registerSender(sender);
    });

    test('a peer delivered meanwhile keeps its id and the message lands at '
        'the server id, not where the peer pushed the row', () async {
      sendText('one');
      // Still uploading behind it.
      outbox.send(
        'c1',
        PlannedSend.single(photo('a'), form: SendForm.media),
        payload: const Note(text: 'photo'),
      );
      await pumpEventQueue();
      expect(sender.requests.single.proposedId, 101);

      // The server gave 101 to the message and 102 to a peer, whose
      // delivery comes first: the rows move up past it.
      outbox.idStrategy('c1').incoming([FakeTailMessage(102)]);
      expect(tail.provisional, ['cm1', 'cm2']);
      expect(tail.tailStart, 103);

      answer.complete(const OutgoingSendAnswer.sent(serverMessageId: 101));
      await pumpEventQueue();

      expect(sent.first.clientMessageId, 'cm1');
      expect((sent.first.position, sent.first.rowAt), (101, null));
      expect(tail.identityAt(101), 'confirmed');
      expect(tail.identityAt(102), 'confirmed');
      expect(statusOf('cm1'), const OutgoingStatus.sent());
      // The row behind it moves down into the freed position, after the
      // peer, and proposes it next; nothing sits twice.
      expect(tail.provisional, ['cm2']);
      expect(tail.identityAt(103), 'cm2');
      expect(tail.identityAt(104), isNull);
      expect(outbox.idStrategy('c1').proposedId, 103);
    });

    test('a fetch that brought the message meanwhile holds it: the row '
        'leaves and no twin stays', () async {
      sendText('one');
      await pumpEventQueue();

      // The data source routes a fetch's rows inside the tail through a
      // move: the server's copy of the message takes 101.
      tail.rebaseTail(order: ['cm1'], insert: [FakeTailMessage(101)]);
      expect(tail.identityAt(102), 'cm1');

      answer.complete(const OutgoingSendAnswer.sent(serverMessageId: 101));
      await pumpEventQueue();

      expect((sent.single.position, sent.single.rowAt), (101, null));
      expect(tail.provisional, isEmpty);
      expect(tail.identityAt(102), isNull);
      expect(outbox.byClientMessageId('c1', 'cm1')!.position, 101);
    });
  });

  test('a row publishing moves to tip+1 first: a later row sent while an '
      'earlier one uploads proposes tip+1', () async {
    outbox.registerSender(sender);
    final photoSend = outbox.send(
      'c1',
      PlannedSend.single(photo('a'), form: SendForm.media),
      payload: const Note(text: 'photo'),
    )!;
    sendText('two');
    await pumpEventQueue();

    expect(photoSend.position, 101);
    expect(sender.requests.single.proposedId, 101);
    expect(sent.single.clientMessageId, 'cm2');
    expect(outbox.byClientMessageId('c1', 'cm1')!.position, 102);
    expect(tail.provisional, ['cm1']);
  });

  test('proposedId is tip+1 after an incoming message', () async {
    sendText('one');
    outbox.idStrategy('c1').incoming([FakeTailMessage(101)]);

    outbox.registerSender(sender);
    await pumpEventQueue();

    expect(sender.requests.single.proposedId, 102);
    expect(sent.single.position, 102);
  });

  test('proposedId follows rows a range fetch put before the tail', () async {
    final diagnostics = RecordingDiagnostics.install();
    sendText('one');
    // The data source routes a fetch's rows inside the tail through this
    // move, not through the strategy.
    tail.rebaseTail(order: ['cm1'], insert: [FakeTailMessage(101)]);

    outbox.registerSender(sender);
    await pumpEventQueue();

    expect(sender.requests.single.proposedId, 102);
    expect(sent.single.position, 102);
    expect(outbox.debugSnapshot('c1').counters.rebases, {'fetch': 1});
    expect(
      diagnostics.whereOp(OutboxOp.tailRebased).first,
      isChatEvent(
        correlation: const ChatCorrelation(
          chatId: 'c1',
          clientMessageId: 'cm1',
          scrollId: '102',
        ),
        fields: {'reason': 'fetch', 'rows': 1, 'inserted': 0, 'from': 101},
      ),
    );
  });

  test('a conflict moves the row past the messages it missed and sends '
      'again in the same publish call, with the same key', () async {
    final diagnostics = RecordingDiagnostics.install();
    sender.answerWith(
      OutgoingSendAnswer.conflict(
        nextId: 103,
        missing: [FakeTailMessage(101), FakeTailMessage(102)],
      ),
    );
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect([for (final r in sender.requests) r.proposedId], [101, 103]);
    expect([for (final r in sender.requests) r.attempt], [1, 2]);
    expect({for (final r in sender.requests) r.clientMessageId}, {'cm1'});
    expect(transfers.attemptsOf(transfers.jobs.single.id), 1);
    expect(statusOf('cm1'), const OutgoingStatus.sent());
    expect(sent.single.position, 103);
    expect(tail.identityAt(101), 'confirmed');
    expect(outbox.debugSnapshot('c1').counters.conflicts, 1);
    expect(diagnostics.whereOp(OutboxOp.publishConflict), [
      isChatEvent(
        level: ChatEventLevel.warning,
        correlation: ChatCorrelation(
          chatId: 'c1',
          clientMessageId: 'cm1',
          jobId: transfers.jobs.single.id,
          scrollId: '101',
        ),
        fields: {'attempt': 1, 'distance': 2},
      ),
    ]);
  });

  test('a third conflict ends the call as a retryable rejection', () async {
    final diagnostics = RecordingDiagnostics.install();
    for (var i = 0; i < 4; i++) {
      sender.answerWith(const OutgoingSendAnswer.conflict(nextId: 200));
    }
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect(sender.requests, hasLength(3));
    expect({for (final r in sender.requests) r.clientMessageId}, {'cm1'});
    expect(
      jobStateOf(0),
      isA<PublishJobState$Failed>().having(
        (state) => state.retryable,
        'retryable',
        isTrue,
      ),
    );
    expect(
      statusOf('cm1'),
      const OutgoingStatus.failed(OutgoingFailure.rejected('chat.conflict')),
    );
    expect(outbox.debugSnapshot('c1').counters.conflicts, 3);
    expect(outbox.debugSnapshot('c1').tail.single.attempts, 3);
    expect(
      [
        for (final event in diagnostics.whereOp(OutboxOp.publishConflict))
          event.fields['attempt'],
      ],
      [1, 2, 3],
    );
    expect(diagnostics.whereOp(OutboxOp.publishConflictExhausted), [
      isChatEvent(level: ChatEventLevel.error, fields: {'attempts': 3}),
    ]);
  });

  test('a replay answered with a later id rebases the row to it', () async {
    final diagnostics = RecordingDiagnostics.install();
    sender.answerWith(
      OutgoingSendAnswer.sent(
        serverMessageId: 102,
        missing: [FakeTailMessage(101)],
      ),
    );
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect(sender.requests, hasLength(1));
    expect([for (final s in sent) (s.position, s.rowAt)], [(102, 102)]);
    expect(tail.identityAt(101), 'confirmed');
    expect(tail.identityAt(102), 'confirmed');
    expect(outbox.byClientMessageId('c1', 'cm1')!.position, 102);
    expect(diagnostics.whereOp(OutboxOp.replayRebased), [
      isChatEvent(
        level: ChatEventLevel.warning,
        correlation: isA<ChatCorrelation>().having(
          (correlation) => correlation.scrollId,
          'scrollId',
          '102',
        ),
        fields: {'distance': 1},
      ),
    ]);
  });

  test('a replay at an id the row cannot reach takes the row out and hands '
      'the host the server id', () async {
    sender.answerWith(const OutgoingSendAnswer.sent(serverMessageId: 90));
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect([for (final s in sent) (s.position, s.rowAt)], [(90, null)]);
    expect(tail.provisional, isEmpty);
    expect(statusOf('cm1'), const OutgoingStatus.sent());
  });

  test(
    'a denial fails the message as denied and calls onDenied once',
    () async {
      final diagnostics = RecordingDiagnostics.install();
      sender.answerWith(
        const OutgoingSendAnswer.denied(
          CapabilityAction.sendText,
          DenialReason.everyone(),
        ),
      );
      outbox.registerSender(sender);

      sendText('one');
      await pumpEventQueue();

      expect(
        statusOf('cm1'),
        const OutgoingStatus.failed(
          OutgoingFailure.denied(CapabilityAction.sendText),
        ),
      );
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendText,
          reason: const DenialReason.everyone(),
        ),
      ]);
      expect(diagnostics.whereOp(OutboxOp.denied), hasLength(1));
      expect(diagnostics.whereCategory(ChatEventCategory.capabilities), [
        isChatEvent(
          fields: containsPair('consumer', CapabilityConsumer.outbox),
        ),
      ]);
    },
  );

  test('a rejection fails the message with its reason, kept out of the '
      'events', () async {
    final diagnostics = RecordingDiagnostics.install();
    sender.answerWith(
      const OutgoingSendAnswer.rejected('flood', retryable: true),
    );
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect(
      statusOf('cm1'),
      const OutgoingStatus.failed(OutgoingFailure.rejected('flood')),
    );
    expect(diagnostics.whereOp(OutboxOp.rejected), [
      isChatEvent(fields: {'reason': 'rejected', 'retryable': true}),
    ]);
    expect(
      diagnostics.events.expand((event) => event.fields.values),
      isNot(contains('flood')),
    );
  });

  group("a server's rejection code stays its own, whatever it spells", () {
    for (final code in [
      'network',
      'tooLarge',
      'sourceLost',
      PublishFailureReason.cancelled,
      PublishFailureReason.publisherError,
      'chat.conflict',
      'chat.denied:sendText',
    ]) {
      test(code, () async {
        sender.answerWith(OutgoingSendAnswer.rejected(code));
        outbox.registerSender(sender);

        sendText('one');
        await pumpEventQueue();

        expect(
          statusOf('cm1'),
          OutgoingStatus.failed(OutgoingFailure.rejected(code)),
        );
      });
    }
  });

  test('a denial journaled for an action this build does not know reads as '
      'unknown', () async {
    sendText('one');

    transfers.setState(
      transfers.jobs.single.id,
      const PublishJobState.failed(
        stage: PublishStage.publish,
        reason: PublishFailureReason('chat.denied:sendHologram'),
        retryable: false,
      ),
    );
    await pumpEventQueue();

    expect(
      statusOf('cm1'),
      const OutgoingStatus.failed(OutgoingFailure.unknown()),
    );
  });

  test('a job whose message this run never restores fails as the '
      "publisher's error once the outbox is disposed", () async {
    final diagnostics = RecordingDiagnostics.install();
    final job = transfers.publish(
      PublishRequest(
        tag: ChatOutbox.tagOf('c1', 'old'),
        items: const [],
        payload: const NotePayloadCodec().encode(const Note(text: 'x')),
        publisher: ChatOutbox.publisherId,
        idempotencyKey: 'old',
      ),
    );

    outbox.registerSender(sender);
    await pumpEventQueue();
    // It waits for its chat's restore.
    expect(
      transfers.jobs.singleWhere((snapshot) => snapshot.id == job).state,
      const PublishJobState.publishing(),
    );

    await outbox.dispose();
    await pumpEventQueue();

    expect(sender.requests, isEmpty);
    expect(
      transfers.jobs.singleWhere((snapshot) => snapshot.id == job).state,
      const PublishJobState.failed(
        stage: PublishStage.publish,
        reason: PublishFailureReason.publisherError,
        retryable: true,
      ),
    );
    expect(diagnostics.whereOp(OutboxOp.senderFailed), [
      isChatEvent(
        correlation: const ChatCorrelation(clientMessageId: 'old'),
        fields: {'errorType': 'unknownMessage'},
      ),
    ]);
  });

  test('a sender that throws fails the message as unknown', () async {
    final diagnostics = RecordingDiagnostics.install();
    sender.throwOnNext(StateError('socket closed'));
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect(
      statusOf('cm1'),
      const OutgoingStatus.failed(OutgoingFailure.unknown()),
    );
    expect(diagnostics.whereOp(OutboxOp.senderFailed), [
      isChatEvent(
        level: ChatEventLevel.error,
        fields: {'errorType': 'StateError'},
      ),
    ]);
  });

  test('reuploadItems reaches the engine once and the message publishes '
      'again', () async {
    final diagnostics = RecordingDiagnostics.install();
    sender.answerWith(
      OutgoingSendAnswer.reuploadItems(const [MediaItemId('cm1:0')]),
    );
    outbox.registerSender(sender);
    outbox.send(
      'c1',
      PlannedSend.single(photo('a'), form: SendForm.media),
      payload: const Note(text: 'photo'),
    );
    final job = transfers.jobs.single.id;

    transfers.setState(
      job,
      const PublishJobState.publishing(),
      items: {'cm1:0': PublishItemState.uploaded(file: RemoteRef('r'))},
    );
    await pumpEventQueue();

    expect(transfers.reuploadsOf(job), [
      {'item:cm1:0'},
    ]);
    expect(sender.requests, hasLength(2));
    expect(sender.requests.first.items.keys, [const MediaItemId('cm1:0')]);
    expect(statusOf('cm1'), const OutgoingStatus.sent());
    expect(diagnostics.whereOp(OutboxOp.reuploadRequested), [
      isChatEvent(
        correlation: isA<ChatCorrelation>().having(
          (correlation) => correlation.mediaItemId,
          'mediaItemId',
          'item:cm1:0',
        ),
        fields: {'items': 1},
      ),
    ]);
  });

  test('the message as stored reaches the host and the job', () async {
    final diagnostics = RecordingDiagnostics.install();
    const stored = Note(text: 'one', silent: true);
    final serverKey = mediaKeyOf('server-photo');
    sender.answerWith(
      OutgoingSendAnswer.sent(
        payloadAsStored: stored,
        serverKeys: {const MediaItemId('cm1:0'): serverKey},
      ),
    );
    outbox.registerSender(sender);

    sendText('one');
    await pumpEventQueue();

    expect(sent.single.payload, const Note(text: 'one'));
    expect(sent.single.payloadAsStored, stored);
    expect(
      jobStateOf(0),
      PublishJobState.completed(const NotePayloadCodec().encode(stored)),
    );
    expect(diagnostics.whereOp(OutboxOp.published), [
      isChatEvent(
        level: ChatEventLevel.info,
        correlation: ChatCorrelation(
          chatId: 'c1',
          clientMessageId: 'cm1',
          jobId: transfers.jobs.single.id,
          scrollId: '101',
        ),
        fields: {
          'attempts': 1,
          'durationMs': isA<int>(),
          'serverKeys': 1,
          'payloadAsStoredDiffers': true,
        },
      ),
    ]);
  });

  test('registering and each attempt are reported', () async {
    final diagnostics = RecordingDiagnostics.install();
    sendText('one');

    outbox.registerSender(sender);
    await pumpEventQueue();

    expect(diagnostics.whereOp(OutboxOp.publisherRegistered), [
      isChatEvent(
        level: ChatEventLevel.info,
        correlation: const ChatCorrelation(chatId: 'c1'),
        fields: {'waiting': 0},
      ),
    ]);
    expect(diagnostics.whereOp(OutboxOp.publishAttempt), [
      isChatEvent(
        level: ChatEventLevel.info,
        correlation: ChatCorrelation(
          chatId: 'c1',
          clientMessageId: 'cm1',
          jobId: transfers.jobs.single.id,
          scrollId: '101',
        ),
        fields: {'attempt': 1, 'proposedId': 101, 'remoteRefs': 0},
      ),
    ]);
  });

  test('under local ids the sender gets no proposal and the row settles at '
      'its local id', () async {
    final local = outboxWith((chatId) => LocalIds(chatId: chatId, tail: tail));
    local.registerSender(sender);

    local.sendText(
      'c1',
      const RichText.plain('one'),
      payload: const Note(text: 'x'),
    );
    await pumpEventQueue();

    expect(sender.requests.single.proposedId, isNull);
    expect([for (final s in sent) (s.position, s.rowAt)], [(101, 101)]);
    expect(
      local.byClientMessageId('c1', 'cm1')!.status,
      const OutgoingStatus.sent(),
    );
  });
}
