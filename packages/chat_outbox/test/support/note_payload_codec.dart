/// A host's message model and its payload codec, as the tests' host writes
/// them.
///
/// Format: UTF-8 JSON, `{"text": <string>, "silent": <bool>}`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:meta/meta.dart';

/// The tests' host message model: user text and one flag.
@immutable
final class Note {
  const Note({required this.text, this.silent = false});

  final String text;
  final bool silent;

  @override
  bool operator ==(Object other) =>
      other is Note && other.text == text && other.silent == silent;

  @override
  int get hashCode => Object.hash(text, silent);
}

/// [Note] to payload bytes and back.
final class NotePayloadCodec extends OutgoingPayloadCodec<Note> {
  const NotePayloadCodec();

  @override
  Converter<Note, Uint8List> get encoder => const _NoteEncoder();

  @override
  Converter<Uint8List, Note> get decoder => const _NoteDecoder();
}

abstract final class _Key {
  static const text = 'text';
  static const silent = 'silent';
}

final class _NoteEncoder extends Converter<Note, Uint8List> {
  const _NoteEncoder();

  @override
  Uint8List convert(Note input) => utf8.encode(
    jsonEncode({_Key.text: input.text, _Key.silent: input.silent}),
  );
}

final class _NoteDecoder extends Converter<Uint8List, Note> {
  const _NoteDecoder();

  @override
  Note convert(Uint8List input) {
    final json = switch (jsonDecode(utf8.decode(input))) {
      final Map<String, Object?> map => map,
      _ => throw const FormatException('A note payload is a JSON object.'),
    };
    return Note(
      text: switch (json[_Key.text]) {
        final String text => text,
        _ => throw const FormatException('A note payload needs a "text".'),
      },
      silent: switch (json[_Key.silent]) {
        final bool silent => silent,
        null => false,
        _ => throw const FormatException('A note\'s "silent" is a bool.'),
      },
    );
  }
}
