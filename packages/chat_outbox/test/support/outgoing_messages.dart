import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';

import 'note_payload_codec.dart';
import 'sends.dart';

/// An outbox over [projection], for tests that set its rows up directly;
/// its jobs go to [transfers] (a new fake unless given).
ChatOutbox<Note> outboxOver(
  OutboxProjection projection, {
  FakeOutboxTransfers? transfers,
}) => ChatOutbox.over(
  projection,
  transfers: transfers ?? FakeOutboxTransfers(),
  codec: const NotePayloadCodec(),
  itemOf: sendItemOf,
  idStrategyOf: fakeIdStrategyOf,
  onSent: (_) {},
  rowOf: fakeRowOf,
);

/// A fresh fake id strategy for [chatId], over its own tail whose newest
/// confirmed message is 100.
OutgoingIdStrategy fakeIdStrategyOf(String chatId) =>
    FakeOutgoingIdStrategy(chatId: chatId);

/// The tests' outgoing row: the message's client message id at its position.
FakeTailMessage fakeRowOf(OutgoingMessage message, Note payload) =>
    FakeTailMessage(message.position, message.clientMessageId);

/// An outgoing message of chat `c1` for the tests, its payload the [Note]
/// [text] through [NotePayloadCodec].
OutgoingMessage outgoingNote(
  String clientMessageId, {
  String chatId = 'c1',
  int position = 101,
  String text = 'hello',
  OutgoingStatus status = const OutgoingStatus.uploading(),
  List<OutgoingItem> items = const [],
}) => OutgoingMessage(
  chatId: chatId,
  clientMessageId: clientMessageId,
  position: position,
  status: status,
  payload: const NotePayloadCodec().encode(Note(text: text)),
  items: items,
);

/// The item `index` of [clientMessageId], keyed as the outbox issues ids.
OutgoingItem outgoingItem(String clientMessageId, int index) => OutgoingItem(
  id: MediaItemId('$clientMessageId:$index'),
  localKey: ContentKey.document('local-$clientMessageId-$index'),
);
