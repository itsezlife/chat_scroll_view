import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_media.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_payload.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';

void main() {
  const codec = DemoOutgoingPayloadCodec();

  test('a payload round-trips through its bytes', () {
    final payload = DemoOutgoingPayload(
      sender: 'Hixie',
      body: 'hello **there**',
      linkPreview: MessageLinkPreview(
        options: LinkPreviewOptions(url: Uri.parse('https://example.com')),
      ),
      invertMedia: true,
    );

    expect(codec.decode(codec.encode(payload)), payload);
    expect(payload.extras, {
      'invertMedia': true,
      'linkPreview': isA<Map<String, Object?>>(),
    });
  });

  test('a payload read from the wire holds its link preview fields typed, '
      'equal whatever order the wire wrote its keys in', () {
    final wire = {
      'linkPreview': {'url': 'https://example.com', 'media': 'large'},
      'invertMedia': true,
    };
    final reordered = {
      'invertMedia': true,
      'linkPreview': {'media': 'large', 'url': 'https://example.com'},
    };

    final a = DemoOutgoingPayload.fromWire(
      sender: 's',
      body: 'b',
      extras: wire,
    );
    final b = DemoOutgoingPayload.fromWire(
      sender: 's',
      body: 'b',
      extras: reordered,
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.invertMedia, isTrue);
    expect(a.linkPreview?.options.url, Uri.parse('https://example.com'));
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

  test("a media message's items round-trip, each fact optional", () {
    final payload = DemoOutgoingPayload(
      sender: 'Hixie',
      body: 'two',
      items: [
        DemoOutgoingItem(
          mediaKey: const MediaKey.remote('local:a'),
          kind: MediaItemKind.video,
          width: 1280,
          height: 720,
          byteSize: 2048,
          duration: const Duration(seconds: 3),
          fileName: 'clip.mp4',
          source: DemoOutgoingSource.key(
            MediaKey.local('00000000-0000-4000-8000-000000000001'),
          ),
        ),
        const DemoOutgoingItem(
          mediaKey: MediaKey.remote('local:b'),
          kind: MediaItemKind.file,
          source: DemoOutgoingSource.file('/files/b.pdf'),
        ),
        const DemoOutgoingItem(
          mediaKey: MediaKey.remote('local:c'),
          kind: MediaItemKind.photo,
        ),
      ],
    );

    expect(codec.decode(codec.encode(payload)), payload);
  });

  test('a payload journaled before items were kept reads as none', () {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'sender': 'a', 'body': 'b'})),
    );

    expect(codec.decode(bytes).items, isEmpty);
  });

  test('an item of the wrong shape throws a FormatException naming it', () {
    Uint8List bytesOf(Object? items) => Uint8List.fromList(
      utf8.encode(
        jsonEncode({'v': 1, 'sender': 'a', 'body': 'b', 'items': items}),
      ),
    );

    expect(
      () => codec.decode(bytesOf('x')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('items'),
        ),
      ),
    );
    expect(
      () => codec.decode(
        bytesOf([
          {'kind': 'photo'},
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('key'),
        ),
      ),
    );
    expect(
      () => codec.decode(
        bytesOf([
          {'key': 'nope', 'kind': 'photo'},
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('"key"'),
        ),
      ),
    );
    expect(
      () => codec.decode(
        bytesOf([
          {
            'key': const MediaKey.remote('x').encoded,
            'kind': 'photo',
            'w': 'wide',
          },
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('"w"'),
        ),
      ),
    );
  });
}
