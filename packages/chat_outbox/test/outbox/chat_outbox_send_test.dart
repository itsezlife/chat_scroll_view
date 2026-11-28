import 'dart:typed_data';

import 'package:attach_model/attach_model.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
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

  Uint8List bytesOf(Note note) => const NotePayloadCodec().encode(note);

  group('the publish request', () {
    test('of a single item', () {
      outbox.send(
        'c1',
        PlannedSend.single(photo('a'), form: SendForm.media),
        payload: const Note(text: 'look'),
      );

      expect(transfers.requests, [
        PublishRequest(
          tag: 'chat:c1:cm1',
          items: [
            PublishItem(
              itemId: 'item:cm1:0',
              key: mediaKeyOf('a'),
              source: PublishSource.prepare(
                inputOf('a'),
                const PreparationIntent.photo(),
              ),
            ),
          ],
          payload: bytesOf(const Note(text: 'look')),
          publisher: 'chat.send',
          idempotencyKey: 'cm1',
          orderingGroup: 'c1',
        ),
      ]);
      // The defaults the chat relies on, named.
      final request = transfers.requests.single;
      expect(request.durability, TransferDurability.system);
      expect(request.failurePolicy, PublishFailurePolicy.wholeJob);
      expect(request.hold, isFalse);
    });

    test('of an album keeps the items in order', () {
      outbox.send(
        'c1',
        PlannedSend.group([photo('a'), video('b')], form: SendForm.media),
        payload: const Note(text: 'two'),
      );

      expect(transfers.requests.single.items, [
        PublishItem(
          itemId: 'item:cm1:0',
          key: mediaKeyOf('a'),
          source: PublishSource.prepare(
            inputOf('a'),
            const PreparationIntent.photo(),
          ),
        ),
        PublishItem(
          itemId: 'item:cm1:1',
          key: mediaKeyOf('b'),
          source: PublishSource.prepare(
            inputOf('b'),
            const PreparationIntent.video(),
          ),
        ),
      ]);
    });

    test('of an item the server already has sends it as remote', () {
      outbox.send(
        'c1',
        PlannedSend.single(photo('remote-a'), form: SendForm.media),
        payload: const Note(text: 'again'),
      );

      expect(
        transfers.requests.single.items.single.source,
        const PublishSource.remote(),
      );
    });

    test('of a text has no items', () {
      outbox.sendText(
        'c1',
        const RichText.plain('hello'),
        payload: const Note(text: 'hello'),
      );

      expect(transfers.requests, [
        PublishRequest(
          tag: 'chat:c1:cm1',
          items: const [],
          payload: bytesOf(const Note(text: 'hello')),
          publisher: 'chat.send',
          idempotencyKey: 'cm1',
          orderingGroup: 'c1',
        ),
      ]);
    });

    test('each send is its own job under a new client message id', () {
      outbox
        ..sendText(
          'c1',
          const RichText.plain('a'),
          payload: const Note(text: 'a'),
        )
        ..sendText(
          'c2',
          const RichText.plain('b'),
          payload: const Note(text: 'b'),
        );

      expect(
        [for (final r in transfers.requests) r.tag],
        ['chat:c1:cm1', 'chat:c2:cm2'],
      );
      expect(
        [for (final r in transfers.requests) r.idempotencyKey],
        ['cm1', 'cm2'],
      );
    });
  });

  group('media item ids', () {
    test('are issued from the client message id and the item index', () {
      final message = outbox.send(
        'c1',
        PlannedSend.group([photo('a'), photo('b')], form: SendForm.media),
        payload: const Note(text: 'two'),
      );

      expect(message?.items, [
        OutgoingItem(id: const MediaItemId('cm1:0'), localKey: localKeyOf('a')),
        OutgoingItem(id: const MediaItemId('cm1:1'), localKey: localKeyOf('b')),
      ]);
    });

    test('the host issues are kept', () {
      final message = outbox.send(
        'c1',
        PlannedSend.group([photo('a'), photo('b')], form: SendForm.media),
        payload: const Note(text: 'two'),
        itemIds: const [MediaItemId('h-a'), MediaItemId('h-b')],
      );

      expect(
        [for (final item in message!.items) item.id],
        const [MediaItemId('h-a'), MediaItemId('h-b')],
      );
      expect(
        [for (final item in transfers.requests.single.items) item.itemId],
        ['item:h-a', 'item:h-b'],
      );
    });
  });

  group('the accepted message', () {
    test('is the outgoing message the lookup answers, fresh', () {
      final message = outbox.send(
        'c1',
        PlannedSend.single(photo('a'), form: SendForm.media),
        payload: const Note(text: 'look'),
      );

      expect(message, isNotNull);
      expect(message!.chatId, 'c1');
      expect(message.clientMessageId, 'cm1');
      // Before the job's first snapshot: its first stage, preparing.
      expect(message.status, const OutgoingStatus.preparing());
      expect(message.payload, bytesOf(const Note(text: 'look')));
      expect(outbox.byClientMessageId('c1', 'cm1'), message);
      expect(outbox.isFreshOutgoing('c1', 'cm1'), isTrue);
    });

    test('of a text starts publishing', () {
      final message = outbox.sendText(
        'c1',
        const RichText.plain('hi'),
        payload: const Note(text: 'hi'),
      );

      expect(message?.status, const OutgoingStatus.publishing());
    });
  });
}
