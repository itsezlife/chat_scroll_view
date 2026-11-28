import 'dart:typed_data';
import 'dart:ui' show AppLifecycleState;

import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_transfer/mpx_transfer.dart';
import 'package:mpx_transfer/testing.dart';

/// What the outbox relies on of [OutboxTransfers], run over the fake and
/// over the real engine through [OutboxTransfers.of], so the fake cannot
/// drift from the engine on these points.
void main() {
  final implementations = <String, Future<OutboxTransfers> Function()>{
    'FakeOutboxTransfers': () async => FakeOutboxTransfers(),
    'OutboxTransfers.of(Transfers)': () async {
      final harness = await UploadsHarness.open(
        lifecycle: ManualPlaybackLifecycleSource(
          initial: AppLifecycleState.resumed,
        ),
        transports: [FakeUploadTransport()],
      );
      addTearDown(harness.transfers.dispose);
      return OutboxTransfers.of(harness.transfers);
    },
  };

  PublishRequest textOf(String tag) => PublishRequest(
    tag: tag,
    items: const [],
    payload: Uint8List.fromList([1, 2, 3]),
    publisher: ChatOutbox.publisherId,
    idempotencyKey: tag,
    orderingGroup: 'c1',
  );

  for (final MapEntry(key: name, value: open) in implementations.entries) {
    group(name, () {
      test('publish answers a distinct id per job', () async {
        final transfers = await open();

        final a = transfers.publish(textOf('chat:c1:a'));
        final b = transfers.publish(textOf('chat:c1:b'));

        expect(a, isNot(b));
      });

      test('watchJobs lists the jobs under a tag prefix, oldest first, '
          'with their ids, tags and publisher', () async {
        final transfers = await open();
        final a = transfers.publish(textOf('chat:c1:a'));
        transfers.publish(textOf('chat:c12:x'));
        final b = transfers.publish(textOf('chat:c1:b'));
        await pumpEventQueue();

        final jobs = await transfers
            .watchJobs(
              const PublishJobFilter(
                tagPrefix: 'chat:c1:',
                publisher: ChatOutbox.publisherId,
              ),
            )
            .first;

        expect(
          [for (final job in jobs) (job.id, job.tag, job.publisher)],
          [
            (a, 'chat:c1:a', ChatOutbox.publisherId),
            (b, 'chat:c1:b', ChatOutbox.publisherId),
          ],
        );
      });

      test(
        "payloadOf answers a job's payload as made",
        () async {
          final transfers = await open();
          final id = transfers.publish(textOf('chat:c1:a'));

          expect(transfers.payloadOf(id), [1, 2, 3]);
        },
        // The engine's facade does not hand a job's payload to its owner
        // yet: the adapter throws until it does.
        skip: name == 'OutboxTransfers.of(Transfers)',
      );

      test('watchJobs gives the current list on listen, then the list '
          'again after a change', () async {
        final transfers = await open();
        transfers.publish(textOf('chat:c1:a'));
        await pumpEventQueue();
        final lists = <List<String?>>[];
        final subscription = transfers
            .watchJobs(const PublishJobFilter(tagPrefix: 'chat:c1:'))
            .listen((jobs) => lists.add([for (final job in jobs) job.tag]));
        addTearDown(subscription.cancel);
        await pumpEventQueue();

        transfers.publish(textOf('chat:c1:b'));
        await pumpEventQueue();

        expect(lists.first, ['chat:c1:a']);
        expect(lists.last, ['chat:c1:a', 'chat:c1:b']);
      });

      Future<PublishJobSnapshot> settled(
        OutboxTransfers transfers,
        PublishJobId id,
      ) async {
        await pumpEventQueue();
        final jobs = await transfers
            .watchJobs(const PublishJobFilter(tagPrefix: 'chat:c1:'))
            .first;
        return jobs.singleWhere((job) => job.id == id);
      }

      test('a job waits for its publisher, and registering it publishes '
          'the payload once with the idempotency key', () async {
        final transfers = await open();
        final id = transfers.publish(textOf('chat:c1:a'));
        await pumpEventQueue();
        final publisher = FakePublisher();

        transfers.registerPublisher(ChatOutbox.publisherId, publisher);
        final job = await settled(transfers, id);

        final call = publisher.calls.single;
        expect(call.payload, [1, 2, 3]);
        expect(call.idempotencyKey, 'chat:c1:a');
        expect(call.items, isEmpty);
        expect(job.state, isA<PublishJobState$Completed>());
      });

      test('a published answer completes the job with its result', () async {
        final transfers = await open();
        final publisher = FakePublisher()
          ..answerWith(
            PublishOutcome.published(result: Uint8List.fromList([9])),
          );
        transfers.registerPublisher(ChatOutbox.publisherId, publisher);

        final job = await settled(
          transfers,
          transfers.publish(textOf('chat:c1:a')),
        );

        expect(job.state, PublishJobState.completed(Uint8List.fromList([9])));
      });

      test(
        'a rejection fails the job at the publish stage with its code',
        () async {
          final transfers = await open();
          final publisher = FakePublisher()
            ..answerWith(
              const PublishOutcome.rejected(reason: 'spam', retryable: true),
            );
          transfers.registerPublisher(ChatOutbox.publisherId, publisher);

          final job = await settled(
            transfers,
            transfers.publish(textOf('chat:c1:a')),
          );

          expect(
            job.state,
            const PublishJobState.failed(
              stage: PublishStage.publish,
              reason: PublishFailureReason('spam'),
              retryable: true,
            ),
          );
        },
      );

      test(
        'a publisher that throws fails the job as a publisher error',
        () async {
          final transfers = await open();
          final publisher = FakePublisher()..throwOnNext(StateError('down'));
          transfers.registerPublisher(ChatOutbox.publisherId, publisher);

          final job = await settled(
            transfers,
            transfers.publish(textOf('chat:c1:a')),
          );

          expect(
            job.state,
            const PublishJobState.failed(
              stage: PublishStage.publish,
              reason: PublishFailureReason.publisherError,
              retryable: true,
            ),
          );
        },
      );
    });
  }
}
