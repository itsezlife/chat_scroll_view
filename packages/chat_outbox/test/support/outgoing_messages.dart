import 'package:chat_outbox/chat_outbox.dart';
import 'package:content_model/content_model.dart';

import 'note_payload_codec.dart';

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
