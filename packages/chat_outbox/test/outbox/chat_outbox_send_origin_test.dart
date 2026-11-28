import 'dart:ui' show Rect;

import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

import '../support/note_payload_codec.dart';
import '../support/outgoing_messages.dart';
import '../support/sends.dart';

void main() {
  const first = Rect.fromLTWH(10, 400, 90, 90);
  const second = Rect.fromLTWH(102, 400, 90, 90);

  late FakeOutboxTransfers transfers;
  late OutboxProjection projection;
  late DateTime clock;
  late ChatOutbox<Note> outbox;

  setUp(() {
    transfers = FakeOutboxTransfers();
    projection = OutboxProjection();
    clock = DateTime.utc(2026, 11, 28, 12);
    outbox = ChatOutbox.over(
      projection,
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: fakeIdStrategyOf,
      rowOf: fakeRowOf,
      clientMessageIds: clientMessageIdsFrom(),
      now: () => clock,
    );
    addTearDown(outbox.dispose);
  });

  PlannedSend album() =>
      PlannedSend.group([photo('a'), photo('b')], form: SendForm.media);

  void sendAlbum({List<Rect?> origins = const [first, second]}) => outbox.send(
    'c1',
    album(),
    payload: const Note(text: 'two'),
    origins: origins,
  );

  const a = MediaItemId('cm1:0');
  const b = MediaItemId('cm1:1');

  test('takeSendOrigin is the media state one-shot origin lookup type', () {
    // The function type the media cells declare; no edge either way.
    expect(outbox.takeSendOrigin, isA<Rect? Function(MediaItemId)>());
  });

  group('origins keyed by item order', () {
    test('are re-keyed to the ids the outbox issues', () {
      sendAlbum();

      expect(outbox.takeSendOrigin(a), first);
      expect(outbox.takeSendOrigin(b), second);
    });

    test('are re-keyed to the ids the host issues', () {
      outbox.send(
        'c1',
        album(),
        payload: const Note(text: 'two'),
        itemIds: const [MediaItemId('host-a'), MediaItemId('host-b')],
        origins: const [first, second],
      );

      expect(outbox.takeSendOrigin(const MediaItemId('host-b')), second);
      expect(outbox.takeSendOrigin(const MediaItemId('host-a')), first);
      expect(outbox.takeSendOrigin(a), isNull);
    });

    test('an item without a rect has no origin', () {
      sendAlbum(origins: const [null, second]);

      expect(outbox.takeSendOrigin(a), isNull);
      expect(outbox.takeSendOrigin(b), second);
    });

    test('must give one entry per item', () {
      expect(
        () => sendAlbum(origins: const [first]),
        throwsA(isA<ArgumentError>()),
      );
      expect(transfers.requests, isEmpty);
    });

    test('a refused send keeps none', () {
      final outbox = ChatOutbox<Note>(
        transfers: transfers,
        codec: const NotePayloadCodec(),
        itemOf: sendItemOf,
        idStrategyOf: fakeIdStrategyOf,
        rowOf: fakeRowOf,
        clientMessageIds: clientMessageIdsFrom(),
        capabilitiesOf: (_) => ValueNotifier(
          const ChatCapabilities(
            slowMode: SlowMode.active(
              interval: Duration(seconds: 30),
              pending: true,
            ),
          ),
        ),
      );
      addTearDown(outbox.dispose);
      final diagnostics = RecordingDiagnostics.install();

      final sent = outbox.send(
        'c1',
        album(),
        payload: const Note(text: 'two'),
        origins: const [first, second],
      );

      expect(sent, isNull);
      expect(outbox.takeSendOrigin(a), isNull);
      expect(diagnostics.whereOp(OutboxOp.sendOriginStored), isEmpty);
    });
  });

  group('each origin is answered once', () {
    test('then null', () {
      sendAlbum();

      expect(outbox.takeSendOrigin(a), first);
      expect(outbox.takeSendOrigin(a), isNull);
      expect(outbox.takeSendOrigin(b), second);
    });

    test('and answered whatever the job state while sending', () async {
      sendAlbum();
      await pumpEventQueue();
      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.uploading(),
      );
      await pumpEventQueue();

      expect(outbox.takeSendOrigin(a), first);
    });
  });

  group('an untaken origin is dropped', () {
    test('when its message is sent', () async {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum();
      outbox.takeSendOrigin(a);
      await pumpEventQueue();

      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.completed(null),
      );
      await pumpEventQueue();

      expect(outbox.takeSendOrigin(b), isNull);
      expect(diagnostics.whereOp(OutboxOp.sendOriginDropped), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            mediaItemId: 'item:cm1:1',
          ),
          fields: {'why': 'sent'},
        ),
      ]);
    });

    test('when its message is cancelled', () {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum();
      final message = outbox.byClientMessageId('c1', 'cm1')!;

      projection.put(message.withStatus(const OutgoingStatus.cancelled()));

      expect(outbox.takeSendOrigin(a), isNull);
      expect(
        diagnostics.whereOp(OutboxOp.sendOriginDropped),
        everyElement(isChatEvent(fields: {'why': 'cancelled'})),
      );
      expect(diagnostics.whereOp(OutboxOp.sendOriginDropped), hasLength(2));
    });

    test('when its message is Absent (cancelled or deleted)', () {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum();

      projection.remove('c1', 'cm1');

      expect(outbox.takeSendOrigin(b), isNull);
      expect(
        diagnostics.whereOp(OutboxOp.sendOriginDropped),
        everyElement(isChatEvent(fields: {'why': 'cancelled'})),
      );
    });

    test('not when its message fails', () async {
      sendAlbum();
      await pumpEventQueue();

      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.failed(
          stage: PublishStage.upload,
          reason: PublishFailureReason('network'),
          retryable: true,
        ),
      );
      await pumpEventQueue();

      expect(outbox.takeSendOrigin(a), first);
    });

    test('after the bound, on the next take', () {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum();

      clock = clock.add(ChatOutbox.sendOriginLifetime);

      expect(outbox.takeSendOrigin(a), isNull);
      expect(diagnostics.whereOp(OutboxOp.sendOriginDropped), [
        isChatEvent(
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            mediaItemId: 'item:cm1:0',
          ),
          fields: {'why': 'expired'},
        ),
        isChatEvent(fields: {'why': 'expired'}),
      ]);
    });

    test('not before the bound', () {
      sendAlbum();

      clock = clock.add(
        ChatOutbox.sendOriginLifetime - const Duration(milliseconds: 1),
      );

      expect(outbox.takeSendOrigin(a), first);
    });

    test('after the bound, on a later send, so memory stays bounded', () {
      sendAlbum();
      clock = clock.add(const Duration(minutes: 1));

      outbox.send(
        'c1',
        PlannedSend.single(photo('c'), form: SendForm.media),
        payload: const Note(text: 'one'),
        origins: const [first],
      );

      final items = outbox.debugSnapshot('c1').tail.expand((row) => row.items);
      expect(
        {for (final item in items) item.mediaItemId: item.sendOriginHeld},
        {'item:cm1:0': false, 'item:cm1:1': false, 'item:cm2:0': true},
      );
    });
  });

  group('diagnostics', () {
    test('sendOriginStored counts the items with and without a rect', () {
      final diagnostics = RecordingDiagnostics.install();

      sendAlbum(origins: const [null, second]);

      expect(diagnostics.whereOp(OutboxOp.sendOriginStored), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
          ),
          fields: {'withOrigin': 1, 'withoutOrigin': 1},
        ),
      ]);
    });

    test('a send without origins stores nothing and reports nothing', () {
      final diagnostics = RecordingDiagnostics.install();

      outbox.send('c1', album(), payload: const Note(text: 'two'));

      expect(diagnostics.whereOp(OutboxOp.sendOriginStored), isEmpty);
      expect(outbox.takeSendOrigin(a), isNull);
    });

    test('sendOriginTaken tells whether one was held, and how long ago', () {
      final diagnostics = RecordingDiagnostics.install();
      sendAlbum();
      clock = clock.add(const Duration(milliseconds: 40));

      outbox
        ..takeSendOrigin(a)
        ..takeSendOrigin(a);

      expect(diagnostics.whereOp(OutboxOp.sendOriginTaken), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'cm1',
            mediaItemId: 'item:cm1:0',
          ),
          fields: {'present': true, 'msSinceAccept': 40},
        ),
        isChatEvent(fields: {'present': false}),
      ]);
    });

    test('an item the outbox does not know reports nothing', () {
      final diagnostics = RecordingDiagnostics.install();

      outbox.takeSendOrigin(const MediaItemId('incoming-1'));

      expect(diagnostics.whereOp(OutboxOp.sendOriginTaken), isEmpty);
    });
  });

  test('the snapshot shows the origins held per item', () {
    sendAlbum(origins: const [first, null]);
    expect(
      outbox
          .debugSnapshot('c1')
          .tail
          .single
          .items
          .map((item) => item.sendOriginHeld),
      [true, false],
    );

    outbox.takeSendOrigin(a);

    expect(
      outbox
          .debugSnapshot('c1')
          .tail
          .single
          .items
          .map((item) => item.sendOriginHeld),
      [false, false],
    );
  });
}
