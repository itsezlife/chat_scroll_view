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
  late ChatOutbox<Note> outbox;

  setUp(() {
    transfers = FakeOutboxTransfers();
    outbox = ChatOutbox(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      clientMessageIds: clientMessageIdsFrom(),
    );
    addTearDown(outbox.dispose);
  });

  /// Sends an album of two photos to `c1` and lets the outbox see its job.
  Future<PublishJobId> sendAlbum() async {
    outbox.send(
      'c1',
      PlannedSend.group([photo('a'), photo('b')], form: SendForm.media),
      payload: const Note(text: 'two'),
    );
    await pumpEventQueue();
    return transfers.jobs.last.id;
  }

  /// The status of `cm1` once its job is in [state], items as given.
  Future<OutgoingStatus?> statusAt(
    PublishJobState state, {
    Map<String, PublishItemState> items = const {},
  }) async {
    final job = await sendAlbum();
    transfers.setState(job, state, items: items);
    await pumpEventQueue();
    return outbox.byClientMessageId('c1', 'cm1')?.status;
  }

  const uploaded = PublishItemState.uploaded();
  const halfway = PublishItemState.uploading(sent: 5, total: 10);

  group('every job state projects to its status', () {
    test('preparing', () async {
      expect(
        await statusAt(const PublishJobState.preparing()),
        const OutgoingStatus.preparing(),
      );
    });

    test('uploading', () async {
      expect(
        await statusAt(const PublishJobState.uploading()),
        const OutgoingStatus.uploading(),
      );
    });

    test('publishing', () async {
      expect(
        await statusAt(const PublishJobState.publishing()),
        const OutgoingStatus.publishing(),
      );
    });

    test('completed is sent', () async {
      expect(
        await statusAt(const PublishJobState.completed(null)),
        const OutgoingStatus.sent(),
      );
    });

    test('awaitingPublisher, everything uploaded, is publishing', () async {
      expect(
        await statusAt(
          const PublishJobState.awaitingPublisher(),
          items: {'item:cm1:0': uploaded, 'item:cm1:1': uploaded},
        ),
        const OutgoingStatus.publishing(),
      );
    });

    for (final reason in PauseReason.values) {
      test(
        'paused(${reason.name}) with an item uploading is uploading',
        () async {
          expect(
            await statusAt(
              PublishJobState.paused(reason),
              items: {'item:cm1:0': uploaded, 'item:cm1:1': halfway},
            ),
            const OutgoingStatus.uploading(),
          );
        },
      );
    }

    test('paused with every item uploaded is publishing', () async {
      expect(
        await statusAt(
          const PublishJobState.paused(PauseReason.systemInterrupted),
          items: {'item:cm1:0': uploaded, 'item:cm1:1': uploaded},
        ),
        const OutgoingStatus.publishing(),
      );
    });

    test('awaitingOwner leaves the status as it was', () async {
      final job = await sendAlbum();
      transfers.setState(job, const PublishJobState.uploading());
      await pumpEventQueue();
      transfers.setState(job, const PublishJobState.awaitingOwner());
      await pumpEventQueue();

      expect(
        outbox.byClientMessageId('c1', 'cm1')?.status,
        const OutgoingStatus.uploading(),
      );
    });
  });

  group('a failed job is failed, its reason closed', () {
    Future<OutgoingStatus?> failedAt(PublishStage stage, String reason) =>
        statusAt(
          PublishJobState.failed(
            stage: stage,
            reason: PublishFailureReason(reason),
            retryable: true,
          ),
        );

    test('the network', () async {
      expect(
        await failedAt(PublishStage.upload, TransferFailureKind.network.name),
        const OutgoingStatus.failed(OutgoingFailure.network()),
      );
    });

    test('a lost source', () async {
      expect(
        await failedAt(
          PublishStage.upload,
          TransferFailureKind.sourceLost.name,
        ),
        const OutgoingStatus.failed(OutgoingFailure.sourceLost()),
      );
    });

    test('too large', () async {
      expect(
        await failedAt(PublishStage.prepare, 'tooLarge'),
        const OutgoingStatus.failed(OutgoingFailure.tooLarge()),
      );
    });

    test("the publisher's rejection keeps its code", () async {
      expect(
        await failedAt(PublishStage.publish, 'chatClosed'),
        const OutgoingStatus.failed(OutgoingFailure.rejected('chatClosed')),
      );
    });

    for (final reason in [
      PublishFailureReason.publisherError,
      PublishFailureReason.reuploadRefused,
      PublishFailureReason.transport,
    ]) {
      test("the engine's own fault $reason at publish is unknown", () async {
        expect(
          await failedAt(PublishStage.publish, reason),
          const OutgoingStatus.failed(OutgoingFailure.unknown()),
        );
      });
    }

    test('an unknown code before publish is unknown', () async {
      expect(
        await failedAt(PublishStage.prepare, 'unreadable'),
        const OutgoingStatus.failed(OutgoingFailure.unknown()),
      );
    });
  });

  test('a job under another chat\'s prefix is ignored', () async {
    final job = await sendAlbum();
    // A chat whose id extends c1's: its tags start with `chat:c1:` too.
    transfers.publish(
      PublishRequest(
        tag: 'chat:c1:x:cm1',
        items: const [],
        payload: const NotePayloadCodec().encode(const Note(text: 'other')),
        publisher: ChatOutbox.publisherId,
      ),
    );
    final other = transfers.jobs.last.id;
    transfers.setState(other, const PublishJobState.completed(null));
    await pumpEventQueue();

    expect(
      outbox.byClientMessageId('c1', 'cm1')?.status,
      const OutgoingStatus.preparing(),
    );
    expect(job, isNot(other));
  });

  test('a job of another chat is not watched under this one', () async {
    await sendAlbum();
    outbox.sendText(
      'c2',
      const RichText.plain('hi'),
      payload: const Note(text: 'hi'),
    );
    await pumpEventQueue();
    transfers.setState(
      transfers.jobs.last.id,
      const PublishJobState.completed(null),
    );
    await pumpEventQueue();

    expect(
      outbox.byClientMessageId('c1', 'cm1')?.status,
      const OutgoingStatus.preparing(),
    );
    expect(
      outbox.byClientMessageId('c2', 'cm2')?.status,
      const OutgoingStatus.sent(),
    );
  });

  test('one watch per chat, ended by dispose', () async {
    await sendAlbum();
    await sendAlbum();
    expect(transfers.watcherCount, 1);

    await outbox.dispose();

    expect(transfers.watcherCount, 0);
  });

  test('a status change keeps the fresh mark unread', () async {
    final job = await sendAlbum();
    transfers.setState(job, const PublishJobState.uploading());
    await pumpEventQueue();

    expect(outbox.isFreshOutgoing('c1', 'cm1'), isTrue);
  });

  group('diagnostics', () {
    test('an accepted send reports accepted and jobCreated, '
        'the payload by its length only', () async {
      final diagnostics = RecordingDiagnostics.install();

      outbox.send(
        'c1',
        PlannedSend.group([
          photo('a'),
          photo('remote-b'),
        ], form: SendForm.media),
        payload: const Note(text: 'secret words'),
      );

      expect(diagnostics.whereOp(OutboxOp.accepted), [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
          ),
          fields: {'kind': 'group', 'items': 2, 'idsIssuedBy': 'outbox'},
        ),
      ]);
      expect(diagnostics.whereOp(OutboxOp.jobCreated), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            jobId: 'job-1',
          ),
          fields: {
            'durability': TransferDurability.system,
            'failurePolicy': PublishFailurePolicy.wholeJob,
            'orderingGroup': true,
            'prepare': 1,
            'prepared': 0,
            'remote': 1,
            // {"text":"secret words","silent":false}
            'payloadBytes': 38,
          },
        ),
      ]);
      for (final event in diagnostics.events) {
        expect('${event.fields}', isNot(contains('secret')));
      }
    });

    test('a host-issued id is reported as such', () {
      final diagnostics = RecordingDiagnostics.install();

      outbox.send(
        'c1',
        PlannedSend.single(photo('a'), form: SendForm.media),
        payload: const Note(text: 'a'),
        itemIds: const [MediaItemId('h-a')],
      );

      expect(diagnostics.whereOp(OutboxOp.accepted).single.fields, {
        'kind': 'single',
        'items': 1,
        'idsIssuedBy': 'host',
      });
    });

    test('a projected change reports statusChanged with the job', () async {
      final job = await sendAlbum();
      final diagnostics = RecordingDiagnostics.install();

      transfers.setState(job, const PublishJobState.uploading());
      await pumpEventQueue();
      // The same state again changes no status.
      transfers.setState(job, const PublishJobState.uploading());
      await pumpEventQueue();
      transfers.setState(
        job,
        const PublishJobState.failed(
          stage: PublishStage.upload,
          reason: PublishFailureReason('network'),
          retryable: true,
        ),
      );
      await pumpEventQueue();

      const correlation = ChatCorrelation(
        chatId: 'c1',
        clientMessageId: 'cm1',
        jobId: 'job-1',
      );
      expect(diagnostics.whereOp(OutboxOp.statusChanged), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: correlation,
          fields: {
            'from': 'preparing',
            'to': 'uploading',
            'jobState': 'uploading',
            'stage': 'upload',
          },
        ),
        isChatEvent(
          correlation: correlation,
          fields: {
            'from': 'uploading',
            'to': 'failed',
            'jobState': 'failed',
            'stage': 'upload',
          },
        ),
      ]);
    });
  });

  group('debugSnapshot', () {
    test('the jobs section: id, state and stage per row', () async {
      final job = await sendAlbum();
      transfers.setState(
        job,
        const PublishJobState.paused(PauseReason.awaitingNetwork),
        items: {'item:cm1:0': halfway},
      );
      await pumpEventQueue();

      final row = outbox.debugSnapshot('c1').tail.single;
      expect(row.jobId, 'job-1');
      expect(row.jobState, 'paused');
      expect(row.stage, 'upload');
      expect(row.status, 'uploading');
    });

    test('a job not seen yet has its id only', () {
      outbox.sendText(
        'c1',
        const RichText.plain('hi'),
        payload: const Note(text: 'hi'),
      );

      final row = outbox.debugSnapshot('c1').tail.single;
      expect((row.jobId, row.jobState, row.stage), ('job-1', null, null));
    });

    test('send in flight and the accepted count', () async {
      final job = await sendAlbum();
      await sendAlbum();
      transfers.setState(job, const PublishJobState.completed(null));
      await pumpEventQueue();

      final snapshot = outbox.debugSnapshot('c1');
      expect(snapshot.sendInFlight, isTrue);
      expect(snapshot.counters.accepted, 2);
      expect(snapshot.tail.first.stage, isNull);
    });
  });
}
