import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:meta/meta.dart';

/// The demo's message model as the outbox keeps it in a publish job: who
/// sends, the markdown body as the composer encoded it, and the rest of the
/// message the bubbles read ([extras]: the link preview and `invertMedia`,
/// in `LinkPreviewWire`'s form).
///
/// A media send's body names its items as the demo's text lines do
/// (`ChatAttachMessages`); the items themselves are the job's.
@immutable
final class DemoOutgoingPayload {
  /// A payload of [body] from [sender], with [extras] beside it.
  const DemoOutgoingPayload({
    required this.sender,
    required this.body,
    this.extras = const {},
  });

  /// Who sends it: the demo's signed-in user.
  final String sender;

  /// The markdown body, as stored.
  final String body;

  /// The message's other fields, JSON values only.
  final Map<String, Object?> extras;

  // The extras are JSON values: their canonical encoding compares nested
  // maps and lists by value, which `==` on a map does not.
  @override
  bool operator ==(Object other) =>
      other is DemoOutgoingPayload &&
      other.sender == sender &&
      other.body == body &&
      jsonEncode(other.extras) == jsonEncode(extras);

  @override
  int get hashCode => Object.hash(sender, body, jsonEncode(extras));

  // The body is user content: it stays out of logs.
  @override
  String toString() =>
      'DemoOutgoingPayload(${body.length} chars, ${extras.length} extras)';
}

/// [DemoOutgoingPayload] to the bytes a publish job journals, and back.
///
/// ## Format
///
/// UTF-8 JSON, one object:
///
/// | Key | Value |
/// |---|---|
/// | `v` | the format version, `1` |
/// | `sender` | [DemoOutgoingPayload.sender], a string |
/// | `body` | [DemoOutgoingPayload.body], a string |
/// | `extras` | [DemoOutgoingPayload.extras], an object; left out when empty |
///
/// The bytes outlive the app (the transfer journal keeps them across a
/// restart), so a decode of another version, of a value of the wrong type
/// or of a missing field throws a [FormatException] naming it: the outbox
/// then reads the message as undecodable.
final class DemoOutgoingPayloadCodec
    extends OutgoingPayloadCodec<DemoOutgoingPayload> {
  /// The codec.
  const DemoOutgoingPayloadCodec();

  /// The version every payload written carries.
  static const int version = 1;

  @override
  Converter<DemoOutgoingPayload, Uint8List> get encoder => const _Encoder();

  @override
  Converter<Uint8List, DemoOutgoingPayload> get decoder => const _Decoder();
}

abstract final class _Key {
  static const String version = 'v';
  static const String sender = 'sender';
  static const String body = 'body';
  static const String extras = 'extras';
}

final class _Encoder extends Converter<DemoOutgoingPayload, Uint8List> {
  const _Encoder();

  @override
  Uint8List convert(DemoOutgoingPayload input) => utf8.encode(
    jsonEncode({
      _Key.version: DemoOutgoingPayloadCodec.version,
      _Key.sender: input.sender,
      _Key.body: input.body,
      if (input.extras.isNotEmpty) _Key.extras: input.extras,
    }),
  );
}

final class _Decoder extends Converter<Uint8List, DemoOutgoingPayload> {
  const _Decoder();

  @override
  DemoOutgoingPayload convert(Uint8List input) {
    final map = switch (jsonDecode(utf8.decode(input))) {
      final Map<String, Object?> map => map,
      _ => throw const FormatException('A payload is a JSON object'),
    };
    if (map[_Key.version] != DemoOutgoingPayloadCodec.version) {
      throw FormatException(
        'Unknown payload version "${_Key.version}": ${map[_Key.version]}',
      );
    }
    return DemoOutgoingPayload(
      sender: _string(map, _Key.sender),
      body: _string(map, _Key.body),
      extras: switch (map[_Key.extras]) {
        null => const {},
        final Map<String, Object?> extras => extras,
        _ => throw const FormatException(
          'Payload field "${_Key.extras}" is not an object',
        ),
      },
    );
  }

  static String _string(Map<String, Object?> map, String key) =>
      switch (map[key]) {
        final String value => value,
        null => throw FormatException('Payload field "$key" is missing'),
        _ => throw FormatException('Payload field "$key" is not a string'),
      };
}
