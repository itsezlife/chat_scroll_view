import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/note_payload_codec.dart';

void main() {
  const codec = NotePayloadCodec();

  test('a payload round-trips through the host codec', () {
    const note = Note(text: 'see you at 7', silent: true);

    final bytes = codec.encode(note);

    expect(bytes, isA<Uint8List>());
    expect(codec.decode(bytes), note);
  });

  test('the host codec is an OutgoingPayloadCodec of its model', () {
    expect(codec, isA<OutgoingPayloadCodec<Note>>());
    expect(codec, isA<Codec<Note, Uint8List>>());
  });
}
