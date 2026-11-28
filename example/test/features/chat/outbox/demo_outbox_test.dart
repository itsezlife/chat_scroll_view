import 'dart:typed_data';

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_media.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

void main() {
  const chat = 'c1';
  const history = 20;

  late FakeOutboxTransfers transfers;
  late DemoChatServer server;
  late DemoOutbox demo;
  late GeneratedChatDataSource source;

  DemoOutbox outboxOver(FakeOutboxTransfers transfers) =>
      DemoOutbox(transfers: transfers, server: server, sender: 'Hixie');

  Future<DemoOutboxChat> openChat({DemoOutbox? over}) async {
    final bound = (over ?? demo).chat(chat);
    await bound.attach(source);
    return bound;
  }

  setUp(() {
    transfers = FakeOutboxTransfers();
    server = DemoChatServer(peerDelay: Duration.zero);
    demo = outboxOver(transfers);
    source = GeneratedChatDataSource(messageCount: history);
  });

  tearDown(() async {
    await demo.dispose();
  });

  OutgoingStatus statusOf(DemoOutboxChat bound, String clientMessageId) => demo
      .outbox
      .byClientMessageId(const ChatId(chat), ClientMessageId(clientMessageId))!
      .status;

  String bodyAt(int id) => switch (source.getMessage(id)) {
    final UserChatMessage message => message.content,
    _ => '',
  };

  PreparedMedia prepared(String path) => PreparedMedia(
    kind: PreparedKind.photo,
    path: path,
    isOriginal: false,
    byteSize: 100,
  );

  test('a text sent at the tail shows its row at once and is sent at the '
      'next id, with no twin from its echo', () async {
    final bound = await openChat();

    final message = bound.sendText('hello')!;

    expect(message.position, history);
    expect(bodyAt(history), contains('hello'));
    expect(source.identityOf!(source.getMessage(history)!), isNotNull);

    await pumpEventQueue();

    expect(
      statusOf(bound, message.clientMessageId),
      const OutgoingStatus.sent(),
    );
    expect(source.getMessage(history), isNotNull);
    expect(source.identityOf!(source.getMessage(history)!), isNull);
    expect(bodyAt(history), contains('hello'));
    expect(source.newestKnownId, history, reason: 'the echo added no twin');
    expect(server.nextIdOf(chat), history + 1);
  });

  test('a peer posting while a send uploads takes its id: the outgoing row '
      'moves up by one, then is sent there, with no twin', () async {
    final bound = await openChat();
    server.script(chat, DemoServerScript.peer);

    final message = bound
        .sendPlanned(
          [PlannedSend.single(AttachItems.photo('p1'), form: SendForm.media)],
          bodies: ['photo'],
          prepared: {const AttachItemId('p1'): prepared('/p1.jpg')},
        )
        .single!;
    await pumpEventQueue();

    expect(
      statusOf(bound, message.clientMessageId),
      const OutgoingStatus.uploading(),
    );
    final row = demo.outbox.byClientMessageId(
      const ChatId(chat),
      message.clientMessageId,
    )!;
    expect(row.position, history + 1);
    expect(source.getMessage(history)!.sender, DemoChatServer.peerName);
    expect(bodyAt(history + 1), contains('photo'));

    final job = transfers.jobs.single.id;
    transfers.setState(job, const PublishJobState.publishing());
    await pumpEventQueue();

    expect(
      statusOf(bound, message.clientMessageId),
      const OutgoingStatus.sent(),
    );
    expect(source.newestKnownId, history + 1);
    expect(source.identityOf!(source.getMessage(history + 1)!), isNull);
  });

  test('a conflict ends sent at the server id, the peer message placed '
      'before it once', () async {
    final bound = await openChat();
    server.script(chat, DemoServerScript.conflict);

    final message = bound.sendText('mine')!;
    await pumpEventQueue();

    expect(
      statusOf(bound, message.clientMessageId),
      const OutgoingStatus.sent(),
    );
    expect(source.getMessage(history)!.sender, DemoChatServer.peerName);
    expect(bodyAt(history + 1), contains('mine'));
    expect(source.newestKnownId, history + 1);
  });

  test('a rejection leaves the message failed in the tail', () async {
    final bound = await openChat();
    server.script(chat, DemoServerScript.reject);

    final message = bound.sendText('nope')!;
    await pumpEventQueue();

    expect(
      statusOf(bound, message.clientMessageId),
      isA<OutgoingStatus>().having((s) => s.name, 'name', 'failed'),
    );
    expect(bodyAt(history), contains('nope'));
    expect(source.identityOf!(source.getMessage(history)!), isNotNull);
  });

  test('a denial fails the message and tells the chat', () async {
    final denied = <CapabilityAction>[];
    final bound = demo.chat(chat);
    await bound.attach(source, onDenied: (action, _) => denied.add(action));
    server.script(chat, DemoServerScript.deny);

    final message = bound.sendText('nope')!;
    await pumpEventQueue();

    expect(
      statusOf(bound, message.clientMessageId),
      const OutgoingStatus.failed(
        OutgoingFailure.denied(CapabilityAction.sendText),
      ),
    );
    expect(denied, [CapabilityAction.sendText]);
  });

  test(
    "a denial reaches its own chat's screen, not the one opened last",
    () async {
      final deniedHere = <CapabilityAction>[];
      final deniedThere = <CapabilityAction>[];
      final here = demo.chat(chat);
      await here.attach(
        source,
        onDenied: (action, _) => deniedHere.add(action),
      );
      final otherSource = GeneratedChatDataSource(messageCount: history);
      addTearDown(otherSource.dispose);
      await demo
          .chat('other')
          .attach(
            otherSource,
            onDenied: (action, _) => deniedThere.add(action),
          );
      server.script(chat, DemoServerScript.deny);

      here.sendText('nope');
      await pumpEventQueue();

      expect(deniedHere, [CapabilityAction.sendText]);
      expect(deniedThere, isEmpty);
    },
  );

  test('after a restart pendingFor puts the messages still sending back at '
      'the tail', () async {
    final bound = await openChat();
    final message = bound
        .sendPlanned(
          [PlannedSend.single(AttachItems.photo('p1'), form: SendForm.media)],
          bodies: ['photo'],
          prepared: {const AttachItemId('p1'): prepared('/p1.jpg')},
        )
        .single!;
    await pumpEventQueue();
    await demo.dispose();

    // The next run: the same engine journal, a fresh history.
    source = GeneratedChatDataSource(messageCount: history);
    server = DemoChatServer(peerDelay: Duration.zero);
    demo = outboxOver(transfers);
    await openChat();

    final restored = demo.outbox.byClientMessageId(
      const ChatId(chat),
      message.clientMessageId,
    )!;
    expect(restored.position, history);
    expect(restored.status, const OutgoingStatus.uploading());
    expect(bodyAt(history), contains('photo'));
    expect(restored.items.single.localKey, message.items.single.localKey);
  });

  test('a restored message whose payload does not decode gets a failed row '
      'in the tail, which Delete takes away', () async {
    transfers.seed(
      PublishRequest(
        tag: ChatOutbox.tagOf(const ChatId(chat), const ClientMessageId('old')),
        items: const [],
        payload: Uint8List.fromList([1, 2, 3]),
        publisher: ChatOutbox.publisherId,
        idempotencyKey: 'old',
        orderingGroup: chat,
      ),
      state: const PublishJobState.awaitingPublisher(),
    );

    await openChat();

    final restored = demo.outbox.byClientMessageId(
      const ChatId(chat),
      const ClientMessageId('old'),
    )!;
    expect(
      restored.status,
      const OutgoingStatus.failed(OutgoingFailure.unknown()),
    );
    expect(source.identityOf!(source.getMessage(restored.position)!), 'old');

    demo.outbox.delete(const ChatId(chat), const ClientMessageId('old'));
    expect(source.getMessage(restored.position), isNull);
  });

  test(
    'a lost source asks the host for the file and retries with it',
    () async {
      final bound = await openChat();
      final message = bound
          .sendPlanned(
            [PlannedSend.single(AttachItems.photo('p1'), form: SendForm.media)],
            bodies: ['photo'],
            prepared: {const AttachItemId('p1'): prepared('/p1.jpg')},
          )
          .single!;
      await pumpEventQueue();
      final job = transfers.jobs.single.id;
      transfers.setState(
        job,
        const PublishJobState.failed(
          stage: PublishStage.upload,
          reason: PublishFailureReason('sourceLost'),
          retryable: true,
        ),
        items: {
          '${message.items.single.id}': const PublishItemState.failed(
            stage: PublishStage.upload,
            reason: PublishFailureReason('sourceLost'),
            retryable: true,
          ),
        },
      );
      await pumpEventQueue();
      final asked = <MediaItemId>[];

      final outcome = await bound.retry(
        message.clientMessageId,
        askForSource: (item) async {
          asked.add(item);
          return SourceBytes.memory(Uint8List(3));
        },
      );

      expect(outcome, OutgoingRetryOutcome.retried);
      expect(asked, [message.items.single.id]);
      expect(transfers.retriedItems.single.$2, '${message.items.single.id}');
    },
  );

  test('the outbox reads the chat capabilities the screen passes, and folds '
      'nothing when no screen is open', () async {
    final capabilities = listen.ValueNotifier(
      const ChatCapabilities().copyWith(
        slowMode: SlowMode.active(
          interval: const Duration(minutes: 1),
          nextSendAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      ),
    );
    addTearDown(capabilities.dispose);
    final bound = demo.chat(chat);
    await bound.attach(source, capabilities: capabilities);

    expect(bound.sendText('held'), isNull);

    bound.detach();
    expect(bound.sendText('free'), isNotNull);
  });

  test(
    'the echo of a sent message is matched by its client message id',
    () async {
      final diagnostics = RecordingDiagnostics.install();
      final bound = await openChat();

      bound.sendText('hello');
      await pumpEventQueue();

      expect(
        diagnostics.events.where((e) => e.op == OutboxOp.echoMatched),
        isNotEmpty,
      );
    },
  );

  test("an outgoing message's events reach the journal, where its logs follow "
      'its client message id', () async {
    final journal = DiagnosticsJournal.memory();
    addTearDown(journal.dispose);
    final previous = ChatDiagnostics.current;
    ChatDiagnostics.current = journal.chatDiagnostics;
    addTearDown(() => ChatDiagnostics.current = previous);
    final bound = await openChat();
    server.script(chat, DemoServerScript.conflict);

    final message = bound.sendText('logged')!;
    await pumpEventQueue();

    final filter = JournalFilter.ofOutgoing(message.clientMessageId);
    final ops = [
      for (final record in journal.records)
        if (filter.matchesBesidesLevel(record)) record.op,
    ];
    expect(ops, containsAll(['accepted', 'fakeServer', 'published']));
    expect(bound.clientMessageIdAt(history + 1), message.clientMessageId);
    expect(
      [for (final record in journal.records) record.fields.values].join(),
      isNot(contains('logged')),
      reason: 'no message text in the journal',
    );
  });

  group('media rows', () {
    List<MediaItem> mediaAt(int id) => switch (source.getMessage(id)) {
      final UserChatMessage message => message.media,
      _ => const [],
    };

    OutgoingMessage sendAlbum(DemoOutboxChat bound) => bound
        .sendPlanned(
          [
            PlannedSend.group([
              AttachItems.photo('p1', width: 400, height: 300),
              AttachItems.photo('p2'),
            ], form: SendForm.media),
          ],
          bodies: ['two'],
          prepared: {
            const AttachItemId('p1'): prepared('/p1.jpg'),
            const AttachItemId('p2'): prepared('/p2.jpg'),
          },
        )
        .single!;

    test("a media send's row carries its items by the outbox's item ids "
        'and local keys, with what the picker knew of them', () async {
      final bound = await openChat();

      final message = sendAlbum(bound);

      final media = mediaAt(message.position);
      expect(
        [for (final item in media) item.id],
        [for (final item in message.items) item.id],
      );
      expect(
        [for (final item in media) item.descriptor.key],
        [for (final item in message.items) item.localKey],
      );
      expect(media.first.kind, MediaItemKind.photo);
      expect(media.first.descriptor.size, const ContentSize(400, 300));
      expect(bodyAt(message.position), 'two');
    });

    test(
      "each item's upload is tracked under the key its cell reads",
      () async {
        final bound = await openChat();

        final message = sendAlbum(bound);

        final request = transfers.requests.single;
        expect(
          [for (final item in request.items) item.key],
          [for (final item in message.items) item.localKey.mediaKey],
        );
        expect([
          for (final item in request.items) item.key,
        ], everyElement(predicate<MediaKey>(DemoOutgoingMedia.isOutgoing)));
      },
    );

    test('an item dropped by its cross leaves the row, which stays the '
        "outbox's", () async {
      final bound = await openChat();
      final message = sendAlbum(bound);
      await pumpEventQueue();

      transfers.cancelUpload(
        transfers.jobs.single.id,
        '${message.items.first.id}',
      );
      await pumpEventQueue();

      final row = source.getMessage(message.position)!;
      expect(
        [for (final item in mediaAt(message.position)) item.id],
        [message.items.last.id],
      );
      expect(source.identityOf!(row), message.clientMessageId);
    });

    test('the sent row keeps its media', () async {
      final bound = await openChat();
      final message = sendAlbum(bound);
      await pumpEventQueue();

      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.publishing(),
      );
      await pumpEventQueue();

      expect(
        statusOf(bound, message.clientMessageId),
        const OutgoingStatus.sent(),
      );
      expect(mediaAt(history), hasLength(2));
    });

    test('after a restart the row carries its items again', () async {
      final bound = await openChat();
      final message = sendAlbum(bound);
      await pumpEventQueue();
      await demo.dispose();

      source = GeneratedChatDataSource(messageCount: history);
      server = DemoChatServer(peerDelay: Duration.zero);
      demo = outboxOver(transfers);
      await openChat();

      expect(
        [for (final item in mediaAt(history)) item.descriptor.key],
        [for (final item in message.items) item.localKey],
      );
    });
  });
}
