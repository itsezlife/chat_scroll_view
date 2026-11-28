import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = DemoOutgoingPayloadCodec();

  test('a payload round-trips through its bytes', () {
    const payload = DemoOutgoingPayload(
      sender: 'Hixie',
      body: 'hello **there**',
      extras: {
        'invertMedia': true,
        'linkPreview': {'url': 'https://example.com'},
      },
    );

    expect(codec.decode(codec.encode(payload)), payload);
  });

  test('a payload without extras writes none and reads back empty', () {
    const payload = DemoOutgoingPayload(sender: 'Hixie', body: 'hi');

    final map =
        jsonDecode(utf8.decode(codec.encode(payload))) as Map<String, Object?>;

    expect(map.containsKey('extras'), isFalse);
    expect(codec.decode(codec.encode(payload)).extras, isEmpty);
  });

  test('bytes of another version, or missing a field, throw a FormatException '
      'naming it', () {
    Uint8List bytesOf(Map<String, Object?> map) =>
        Uint8List.fromList(utf8.encode(jsonEncode(map)));

    expect(
      () => codec.decode(bytesOf({'v': 9, 'sender': 'a', 'body': 'b'})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('v'),
        ),
      ),
    );
    expect(
      () => codec.decode(bytesOf({'v': 1, 'body': 'b'})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('sender'),
        ),
      ),
    );
    expect(
      () => codec.decode(bytesOf({'v': 1, 'sender': 'a', 'body': 3})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('body'),
        ),
      ),
    );
    expect(
      () => codec.decode(Uint8List.fromList(utf8.encode('[1]'))),
      throwsFormatException,
    );
  });
}
