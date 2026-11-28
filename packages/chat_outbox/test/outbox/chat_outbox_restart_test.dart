import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

import '../support/note_payload_codec.dart';
import '../support/sends.dart';

/// A restart: the engine's journal holds the jobs an earlier run made, and a
/// new outbox over it reads each chat's outgoing messages back.
void main() {
  late FakeOutboxTransfers transfers;
  late FakeOutgoingTail tail;
  late RecordingOutgoingSender<Note> sender;
  late ChatOutbox<Note> outbox;

  ChatOutbox<Note> restartedOutbox({
    IChatMessage Function(OutgoingMessage message)? undecodableRowOf,
  }) {
    final outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: (chatId) => SequentialServerIds(chatId: chatId, tail: tail),
      onSent: (_) {},
      rowOf: (message, payload) =>
          FakeTailMessage(message.position, message.clientMessageId),
      localKeyOf: (mediaKey) => ContentKey.document('local:$mediaKey'),
      undecodableRowOf: undecodableRowOf,
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(outbox.dispose);
    return outbox;
  }

  setUp(() {
    transfers = FakeOutboxTransfers();
    tail = FakeOutgoingTail();
    sender = RecordingOutgoingSender();
    outbox = restartedOutbox(
      undecodableRowOf: (message) =>
          FakeTailMessage(message.position, message.clientMessageId),
    );
  });

  /// Seeds the journal with the job of message [clientMessageId] of
  /// [chatId], as an earlier run made it.
  PublishJobId seed(
    String clientMessageId, {
    String chatId = 'c1',
    String text = 'hello',
    List<String> items = const [],
    PublishJobState? state,
    Uint8List? payload,
  }) => transfers.seed(
    PublishRequest(
      tag: ChatOutbox.tagOf(chatId, clientMessageId),
      items: [
        for (final (index, item) in items.indexed)
          PublishItem(
            itemId: '${MediaItemId('$clientMessageId:$index')}',
            key: mediaKeyOf(item),
            source: const PublishSource.remote(),
          ),
      ],
      payload: payload ?? const NotePayloadCodec().encode(Note(text: text)),
      publisher: ChatOutbox.publisherId,
      idempotencyKey: clientMessageId,
      orderingGroup: chatId,
    ),
    state: state,
  );

  const failedNetwork = PublishJobState.failed(
    stage: PublishStage.upload,
    reason: PublishFailureReason('network'),
    retryable: true,
  );
  const failedRejected = PublishJobState.failed(
    stage: PublishStage.publish,
    reason: PublishFailureReason('chat.rejected:spam'),
    retryable: false,
  );

  test('pendingFor gives the messages with their status at fresh '
      'positions: sending ones in creation order, failed ones below', () async {
    seed('a', state: const PublishJobState.uploading());
    seed('b', state: failedNetwork);
    seed('c', state: const PublishJobState.awaitingPublisher());
    seed('d', state: failedRejected);

    final pending = await outbox.pendingFor('c1');

    expect(
      [
        for (final message in pending)
          (message.clientMessageId, message.position, message.status),
      ],
      [
        ('a', 101, const OutgoingStatus.uploading()),
        ('c', 102, const OutgoingStatus.publishing()),
        ('b', 103, const OutgoingStatus.failed(OutgoingFailure.network())),
        (
          'd',
          104,
          const OutgoingStatus.failed(OutgoingFailure.rejected('spam')),
        ),
      ],
    );
    expect(tail.provisional, ['a', 'c', 'b', 'd']);
    expect(outbox.byClientMessageId('c1', 'b')?.position, 103);
  });

  test(
    'a completed job is not pending, and another chat is not read',
    () async {
      seed('a', state: PublishJobState.completed(Uint8List(0)));
      seed('x', chatId: 'c2');
      seed('y', chatId: 'c12');

      expect(await outbox.pendingFor('c1'), isEmpty);
      expect(tail.inserted, isEmpty);
    },
  );

  test('a restored message keeps its payload and its items', () async {
    seed('a', text: 'hi', items: ['p1', 'p2']);

    final message = (await outbox.pendingFor('c1')).single;

    expect(
      const NotePayloadCodec().decode(message.payload),
      const Note(text: 'hi'),
    );
    expect(message.items, [
      OutgoingItem(
        id: const MediaItemId('a:0'),
        localKey: ContentKey.document('local:${mediaKeyOf('p1')}'),
      ),
      OutgoingItem(
        id: const MediaItemId('a:1'),
        localKey: ContentKey.document('local:${mediaKeyOf('p2')}'),
      ),
    ]);
  });

  test('a restored row is not fresh', () async {
    seed('a');

    await outbox.pendingFor('c1');

    expect(outbox.isFreshOutgoing('c1', 'a'), isFalse);
  });

  test('pendingFor again places nothing twice', () async {
    seed('a');
    await outbox.pendingFor('c1');

    final again = await outbox.pendingFor('c1');

    expect([for (final message in again) message.clientMessageId], ['a']);
    expect(tail.inserted, hasLength(1));
  });

  test('a restored message follows its job', () async {
    final job = seed('a', state: const PublishJobState.uploading());
    await outbox.pendingFor('c1');

    transfers.setState(job, failedNetwork);
    await pumpEventQueue();

    expect(
      outbox.byClientMessageId('c1', 'a')?.status,
      const OutgoingStatus.failed(OutgoingFailure.network()),
    );
    expect(tail.provisional, ['a']);
  });

  test('registering the sender releases the jobs awaiting it', () async {
    final diagnostics = RecordingDiagnostics.install();
    final job = seed(
      'a',
      text: 'one',
      state: const PublishJobState.awaitingPublisher(),
    );
    await outbox.pendingFor('c1');

    outbox.registerSender(sender);
    await pumpEventQueue();

    final request = sender.requests.single;
    expect(request.clientMessageId, 'a');
    expect(request.payload, const Note(text: 'one'));
    expect(request.proposedId, 101);
    expect(
      transfers.jobs.singleWhere((snapshot) => snapshot.id == job).state,
      isA<PublishJobState$Completed>(),
    );
    expect(
      outbox.byClientMessageId('c1', 'a')?.status,
      const OutgoingStatus.sent(),
    );
    expect(diagnostics.whereOp(OutboxOp.publisherRegistered).single.fields, {
      'waiting': 1,
    });
  });

  test('a job the sender reaches before its chat is restored waits for '
      'the restore, then publishes', () async {
    final diagnostics = RecordingDiagnostics.install();
    final job = seed('a', state: const PublishJobState.awaitingPublisher());
    outbox.registerSender(sender);
    await pumpEventQueue();
    expect(sender.requests, isEmpty);

    await outbox.pendingFor('c1');
    await pumpEventQueue();

    expect(sender.requests.single.clientMessageId, 'a');
    expect(
      transfers.jobs.singleWhere((snapshot) => snapshot.id == job).state,
      isA<PublishJobState$Completed>(),
    );
    expect(diagnostics.whereOp(OutboxOp.senderFailed), isEmpty);
  });

  test('a job still waiting for its restore when the outbox is disposed '
      "fails as the publisher's error", () async {
    final diagnostics = RecordingDiagnostics.install();
    final job = seed('a', state: const PublishJobState.awaitingPublisher());
    outbox.registerSender(sender);
    await pumpEventQueue();

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
        correlation: const ChatCorrelation(clientMessageId: 'a'),
        fields: {'errorType': 'unknownMessage'},
      ),
    ]);
  });

  group('an undecodable payload', () {
    final garbage = Uint8List.fromList(utf8.encode('secret words, not json'));

    test(
      'is failed(unknown) at the bottom, reported without its bytes',
      () async {
        final diagnostics = RecordingDiagnostics.install();
        seed('a', state: const PublishJobState.uploading());
        final job = seed(
          'b',
          payload: garbage,
          state: const PublishJobState.uploading(),
        );
        seed('c', state: const PublishJobState.uploading());

        final pending = await outbox.pendingFor('c1');

        expect(
          [
            for (final message in pending)
              (message.clientMessageId, message.status),
          ],
          [
            ('a', const OutgoingStatus.uploading()),
            ('c', const OutgoingStatus.uploading()),
            ('b', const OutgoingStatus.failed(OutgoingFailure.unknown())),
          ],
        );
        expect(diagnostics.whereOp(OutboxOp.payloadDecodeFailed), [
          isChatEvent(
            level: ChatEventLevel.error,
            correlation: ChatCorrelation(
              chatId: 'c1',
              clientMessageId: 'b',
              jobId: job,
            ),
            fields: {
              'errorType': 'FormatException',
              'payloadBytes': garbage.length,
            },
          ),
        ]);
        for (final event in diagnostics.events) {
          expect('${event.fields}', isNot(contains('secret')));
        }
      },
    );

    test('stays failed(unknown) while its job moves on', () async {
      final job = seed(
        'b',
        payload: garbage,
        state: const PublishJobState.uploading(),
      );
      await outbox.pendingFor('c1');

      transfers.setState(job, const PublishJobState.publishing());
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'b')?.status,
        const OutgoingStatus.failed(OutgoingFailure.unknown()),
      );
    });

    test('without a row for it, is not placed', () async {
      final diagnostics = RecordingDiagnostics.install();
      final plain = restartedOutbox();
      seed('b', payload: garbage);

      expect(await plain.pendingFor('c1'), isEmpty);
      expect(tail.inserted, isEmpty);
      expect(diagnostics.whereOp(OutboxOp.payloadDecodeFailed), hasLength(1));
    });
  });

  test('a job under the prefix whose tag does not parse is left alone and '
      'warned once', () async {
    final diagnostics = RecordingDiagnostics.install();
    final empty = transfers.seed(
      PublishRequest(
        tag: 'chat:c1:',
        items: const [],
        payload: Uint8List(0),
        publisher: ChatOutbox.publisherId,
      ),
    );
    seed('a');

    final pending = await outbox.pendingFor('c1');
    await outbox.pendingFor('c1');
    transfers.setState(empty, const PublishJobState.uploading());
    await pumpEventQueue();

    expect([for (final message in pending) message.clientMessageId], ['a']);
    expect(tail.provisional, ['a']);
    expect(
      transfers.jobs.singleWhere((job) => job.id == empty).state,
      const PublishJobState.uploading(),
    );
    expect(diagnostics.whereOp(OutboxOp.foreignJob), [
      isChatEvent(
        level: ChatEventLevel.warning,
        correlation: ChatCorrelation(chatId: 'c1', jobId: empty),
        fields: {'why': 'emptyId'},
      ),
    ]);
  });

  test('a tag with a separator past the prefix, or an item id that is no '
      'media item id, is left alone with its reason', () async {
    final diagnostics = RecordingDiagnostics.install();
    final nested = transfers.seed(
      PublishRequest(
        tag: 'chat:c1:x:y',
        items: const [],
        payload: Uint8List(0),
        publisher: ChatOutbox.publisherId,
      ),
    );
    final badItem = transfers.seed(
      PublishRequest(
        tag: ChatOutbox.tagOf('c1', 'z'),
        items: [
          PublishItem(
            itemId: 'not-a-media-item-id',
            key: mediaKeyOf('p1'),
            source: const PublishSource.remote(),
          ),
        ],
        payload: const NotePayloadCodec().encode(const Note(text: 'z')),
        publisher: ChatOutbox.publisherId,
      ),
    );

    expect(await outbox.pendingFor('c1'), isEmpty);

    expect(
      [
        for (final event in diagnostics.whereOp(OutboxOp.foreignJob))
          (event.correlation.jobId, event.fields['why']),
      ],
      [('$nested', 'separator'), ('$badItem', 'itemId')],
    );
  });

  test('restored reports the counts; each row is allocated after a '
      'restart', () async {
    final diagnostics = RecordingDiagnostics.install();
    seed('a', state: const PublishJobState.uploading());
    seed('b', state: failedNetwork);
    seed('c', state: const PublishJobState.awaitingPublisher());

    await outbox.pendingFor('c1');

    expect(diagnostics.whereOp(OutboxOp.restored), [
      isChatEvent(
        level: ChatEventLevel.info,
        correlation: const ChatCorrelation(chatId: 'c1'),
        fields: {'sending': 2, 'failed': 1, 'awaitingPublisher': 1},
      ),
    ]);
    expect(
      [
        for (final event in diagnostics.whereOp(OutboxOp.positionAllocated))
          event.fields['allocation'],
      ],
      ['restart', 'restart', 'restart'],
    );
  });

  test(
    'the snapshot counts the restores and shows the restored jobs',
    () async {
      final a = seed('a', state: const PublishJobState.uploading());
      final b = seed('b', state: failedNetwork);

      await outbox.pendingFor('c1');
      final snapshot = outbox.debugSnapshot('c1');

      expect(snapshot.counters.restores, 2);
      expect(
        [
          for (final row in snapshot.tail)
            (row.clientMessageId, row.jobId, row.jobState),
        ],
        [('a', '$a', 'uploading'), ('b', '$b', 'failed')],
      );
    },
  );

  test('a restore after the restart sends on with new messages after the '
      'restored ones', () async {
    seed('a', state: const PublishJobState.uploading());
    await outbox.pendingFor('c1');

    final sent = outbox.sendText(
      'c1',
      const RichText.plain('new'),
      payload: const Note(text: 'new'),
    )!;

    expect(sent.position, 102);
    expect(tail.provisional, ['a', 'cm1']);
  });

  test('restored rows go in as no send of the user\'s, so a reader '
      'scrolled up is not pulled down; a new send still is', () async {
    final answer = Completer<OutgoingSendAnswer<Note>>();
    sender.answerBy((_) => answer.future);
    seed('a', state: const PublishJobState.awaitingPublisher());
    seed('b', state: failedNetwork);
    outbox.registerSender(sender);

    await outbox.pendingFor('c1');
    await pumpEventQueue();
    // The restored job publishes, its answer still out.
    expect(sender.requests.single.clientMessageId, 'a');

    expect([for (final row in tail.inserted) row.id], [101, 102]);
    expect(tail.insertedWithoutFollow, [101, 102]);

    outbox.sendText(
      'c1',
      const RichText.plain('new'),
      payload: const Note(text: 'new'),
    );
    expect([for (final row in tail.inserted) row.id], [101, 102, 103]);
    expect(tail.insertedWithoutFollow, [101, 102]);

    answer.complete(const OutgoingSendAnswer.sent(serverMessageId: 101));
    await pumpEventQueue();
    expect(
      outbox.byClientMessageId('c1', 'a')?.status,
      const OutgoingStatus.sent(),
    );
  });

  test(
    'a message the server accepted before the restart, met in fetched '
    'history, settles there: its restored row leaves and no twin stays',
    () async {
      final diagnostics = RecordingDiagnostics.install();
      final answer = Completer<OutgoingSendAnswer<Note>>();
      sender.answerBy((_) => answer.future);
      final statuses = <OutgoingStatus>[];
      outbox = ChatOutbox<Note>(
        transfers: transfers,
        codec: const NotePayloadCodec(),
        itemOf: sendItemOf,
        idStrategyOf: (chatId) =>
            SequentialServerIds(chatId: chatId, tail: tail),
        rowOf: (message, payload) =>
            FakeTailMessage(message.position, message.clientMessageId),
        onSent: (_) {},
        onStatusChanged: (message) => statuses.add(message.status),
        localKeyOf: (mediaKey) => ContentKey.document('local:$mediaKey'),
        clientMessageIds: clientMessageIdsFrom(),
      );
      addTearDown(outbox.dispose);
      // The journal still has the job publishing: the app died after the
      // server stored the message at 100, before the job completed.
      seed('a', state: const PublishJobState.publishing());
      seed('b', state: const PublishJobState.uploading());
      outbox.registerSender(sender);
      await outbox.pendingFor('c1');
      await pumpEventQueue();
      expect(tail.provisional, ['a', 'b']);
      expect(sender.requests.single.clientMessageId, 'a');

      // The chat's history (the tip, 100) is the server's copy of 'a'.
      final settled = outbox.settleFromHistory('c1', 'a', serverId: 100);

      expect(settled?.status, const OutgoingStatus.sent());
      expect(settled?.position, 100);
      expect(tail.provisional, ['b']);
      expect(tail.identityAt(101), 'b');
      expect(outbox.byClientMessageId('c1', 'a')?.position, 100);
      expect(statuses, [const OutgoingStatus.sent()]);
      expect(outbox.cancel('c1', 'a'), OutgoingCancelOutcome.tooLate);
      expect(
        diagnostics.whereOp(OutboxOp.tailRebased).last.fields,
        containsPair('reason', 'removed'),
      );

      // The replay's answer finds it settled: nothing moves again.
      answer.complete(const OutgoingSendAnswer.sent(serverMessageId: 100));
      await pumpEventQueue();
      expect(tail.provisional, ['b']);
      expect(
        outbox.byClientMessageId('c1', 'a')?.status,
        const OutgoingStatus.sent(),
      );
      expect(statuses, [const OutgoingStatus.sent()]);
    },
  );

  test('settleFromHistory answers null for a message the outbox does not '
      'hold', () async {
    await outbox.pendingFor('c1');
    expect(outbox.settleFromHistory('c1', 'nope', serverId: 100), isNull);
  });
}
