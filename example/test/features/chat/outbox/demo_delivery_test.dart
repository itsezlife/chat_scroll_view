/// What an outgoing bubble's time pill reads from the demo's outbox
/// binding: the outbox's status while the message is on its way or failed,
/// the server's read status once it is sent; the announcements of a send;
/// Retry and Delete by row, each guarded against a burst.
library;

import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:content_model/content_model.dart' show MediaItemId;
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

void main() {
  const chat = 'c1';
  const history = 20;

  late FakeOutboxTransfers transfers;
  late DemoChatServer server;
  late DemoOutbox demo;
  late GeneratedChatDataSource source;
  late List<String> announced;

  setUp(() {
    transfers = FakeOutboxTransfers();
    server = DemoChatServer(peerDelay: Duration.zero);
    demo = DemoOutbox(transfers: transfers, server: server);
    source = GeneratedChatDataSource(messageCount: history);
    announced = [];
  });

  tearDown(() async {
    await demo.dispose();
  });

  Future<DemoOutboxChat> openChat({
    Future<SourceBytes?> Function(MediaItemId item)? askForSource,
  }) async {
    final bound = demo.chat(chat);
    await bound.attach(
      source,
      announce: announced.add,
      askForSource: askForSource,
    );
    return bound;
  }

  PlannedSend photo(String id) =>
      PlannedSend.single(AttachItems.photo(id), form: SendForm.media);

  const prepared = PreparedMedia(
    kind: PreparedKind.photo,
    path: '/p1.jpg',
    isOriginal: false,
    byteSize: 100,
  );

  OutgoingMessage sendPhoto(DemoOutboxChat bound) => bound
      .sendPlanned(
        [photo('p1')],
        bodies: ['photo'],
        prepared: {const AttachItemId('p1'): prepared},
      )
      .single!;

  PublishJobId jobOf(OutgoingMessage message) => transfers.jobs
      .singleWhere((job) => job.tag == 'chat:$chat:${message.clientMessageId}')
      .id;

  Future<void> failUpload(
    OutgoingMessage message, {
    String reason = 'network',
  }) async {
    transfers.setState(
      jobOf(message),
      PublishJobState.failed(
        stage: PublishStage.upload,
        reason: PublishFailureReason(reason),
        retryable: true,
      ),
      items: {
        for (final item in message.items)
          '${item.id}': PublishItemState.failed(
            stage: PublishStage.upload,
            reason: PublishFailureReason(reason),
            retryable: true,
          ),
      },
    );
    await pumpEventQueue();
  }

  group('the time pill', () {
    test('reads sending while the message is on its way', () async {
      final bound = await openChat();

      final message = sendPhoto(bound);
      await pumpEventQueue();

      expect(bound.deliveryOf(message.position), DemoDelivery.sending);
    });

    test('reads one check once sent, and the second check only when the '
        'server says the message was read', () async {
      final bound = await openChat();
      var changes = 0;
      bound.deliveryChanges.addListener(() => changes++);

      bound.sendText('hello');
      await pumpEventQueue();

      expect(
        demo.outbox
            .byClientMessageId(
              const ChatId(chat),
              ClientMessageId(transfers.requests.single.idempotencyKey!),
            )
            ?.status,
        const OutgoingStatus.sent(),
      );
      expect(bound.deliveryOf(history), DemoDelivery.sent);

      changes = 0;
      server.markRead(chat, history);

      expect(bound.deliveryOf(history), DemoDelivery.read);
      expect(changes, 1);
    });

    test('reads the history the chat held before the run as read', () async {
      await openChat();

      expect(server.readUpTo(chat).value, history - 1);
    });

    test('reads not sent for a failed message, and redraws on the failure '
        'though the row stays where it is', () async {
      final bound = await openChat();
      final message = sendPhoto(bound);
      await pumpEventQueue();
      var changes = 0;
      bound.deliveryChanges.addListener(() => changes++);

      await failUpload(message);

      expect(bound.deliveryOf(message.position), DemoDelivery.notSent);
      expect(changes, greaterThan(0));
    });
  });

  group('announcements', () {
    test('a send announces its start and its end only', () async {
      final bound = await openChat();

      final message = sendPhoto(bound);
      await pumpEventQueue();
      transfers.setState(jobOf(message), const PublishJobState.uploading());
      await pumpEventQueue();
      transfers.setState(jobOf(message), const PublishJobState.publishing());
      await pumpEventQueue();

      expect(announced, [
        DemoOutgoingStrings.sending,
        DemoOutgoingStrings.sent,
      ]);
    });

    test('a failed send ends as not sent', () async {
      final bound = await openChat();

      final message = sendPhoto(bound);
      await pumpEventQueue();
      await failUpload(message);

      expect(announced, [
        DemoOutgoingStrings.sending,
        DemoOutgoingStrings.notSent,
      ]);
    });
  });

  group('Retry and Delete by row', () {
    test('a burst of retries repeats the message once', () async {
      final bound = await openChat();
      final message = sendPhoto(bound);
      await pumpEventQueue();
      await failUpload(message);
      final at = demo.outbox.byClientMessageId(
        const ChatId(chat),
        message.clientMessageId,
      )!;

      final outcomes = await Future.wait([
        for (var i = 0; i < 10; i++) bound.retryAt(at.position),
      ]);

      expect(transfers.retried, [jobOf(message)]);
      expect(
        outcomes.where((o) => o == OutgoingRetryOutcome.retried),
        hasLength(1),
      );
      expect(bound.deliveryOf(at.position), DemoDelivery.sending);
    });

    test(
      'a burst of retries of a lost source asks for the file once',
      () async {
        var asked = 0;
        final answer = Completer<SourceBytes?>();
        final bound = await openChat(
          askForSource: (_) {
            asked++;
            return answer.future;
          },
        );
        final message = sendPhoto(bound);
        await pumpEventQueue();
        await failUpload(message, reason: 'sourceLost');
        final at = demo.outbox.byClientMessageId(
          const ChatId(chat),
          message.clientMessageId,
        )!;

        final retries = [
          for (var i = 0; i < 10; i++) bound.retryAt(at.position),
        ];
        await pumpEventQueue();
        answer.complete(SourceBytes.file('/again.jpg', size: 100));
        await Future.wait(retries);

        expect(asked, 1);
        expect(transfers.retriedItems, hasLength(1));
      },
    );

    test('a burst of deletes takes the message away once', () async {
      final bound = await openChat();
      final message = sendPhoto(bound);
      await pumpEventQueue();
      await failUpload(message);
      final at = demo.outbox.byClientMessageId(
        const ChatId(chat),
        message.clientMessageId,
      )!;
      final job = jobOf(message);

      for (var i = 0; i < 10; i++) {
        bound.deleteAt(at.position);
      }
      await pumpEventQueue();

      expect(transfers.cancelled, [job]);
      expect(
        demo.outbox.byClientMessageId(
          const ChatId(chat),
          message.clientMessageId,
        ),
        isNull,
      );
      expect(source.getMessage(at.position), isNull);
    });

    test(
      'a row that is not an outgoing message has no Retry or Delete',
      () async {
        final bound = await openChat();

        expect(await bound.retryAt(history - 1), isNull);
        expect(bound.deleteAt(history - 1), isNull);
        expect(bound.isFailedAt(history - 1), isFalse);
      },
    );
  });
}
