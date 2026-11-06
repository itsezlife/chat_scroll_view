/// The Giphy client: what it asks for and what it makes of the answer.
///
/// **Seam:** [GiphyClient] over a fake `http.Client`, observed through the
/// requests the fake received and the clips and failures the client returns.
/// The JSON is written by hand in the shape of the API's documentation (only
/// the fields the client reads); no real response is copied.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _clipJson(
  String id, {
  String title = 'a cat',
  Map<String, Object?>? images,
}) => jsonEncode({
  'id': id,
  'title': title,
  'images':
      images ??
      {
        'fixed_width': {
          'url': 'https://media.example/$id/200w.gif',
          'mp4': 'https://media.example/$id/200w.mp4',
          'width': '200',
          'height': '150',
        },
      },
});

String _page(
  List<String> clips, {
  int total = 100,
  int offset = 0,
  int? count,
}) =>
    '{"data":[${clips.join(',')}],'
    '"pagination":{"total_count":$total,"count":${count ?? clips.length},'
    '"offset":$offset},"meta":{"status":200}}';

GiphyClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  Duration timeout = const Duration(seconds: 5),
}) => GiphyClient(
  apiKey: 'secret-key',
  client: MockClient(handler),
  timeout: timeout,
);

void main() {
  group('trending', () {
    test('asks for a page at the offset and keys the request', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response(_page([_clipJson('a')]), 200);
      });

      await client.trending(offset: 48);

      expect(seen.url.path, '/v1/gifs/trending');
      expect(seen.url.queryParameters['api_key'], 'secret-key');
      expect(seen.url.queryParameters['offset'], '48');
      expect(seen.url.queryParameters['limit'], '${client.pageSize}');
    });

    test(
      'makes a clip of the mp4 rendition with the size the API gives',
      () async {
        final client = _client(
          (_) async => http.Response(_page([_clipJson('a')]), 200),
        );

        final page = await client.trending();

        final clip = page.clips.single;
        expect(clip.id, 'a');
        expect(clip.title, 'a cat');
        expect(clip.url, Uri.parse('https://media.example/a/200w.mp4'));
        expect((clip.width, clip.height), (200, 150));
      },
    );

    test('falls back to a smaller rendition, and then to the gif', () async {
      final client = _client(
        (_) async => http.Response(
          _page([
            _clipJson(
              'small',
              images: {
                'fixed_width': {'width': '200', 'height': '100'},
                'fixed_width_small': {
                  'mp4': 'https://media.example/small/100w.mp4',
                  'width': '100',
                  'height': '50',
                },
              },
            ),
            _clipJson(
              'gifonly',
              images: {
                'fixed_width': {
                  'url': 'https://media.example/gifonly/200w.gif',
                  'width': '200',
                  'height': '100',
                },
              },
            ),
          ]),
          200,
        ),
      );

      final clips = (await client.trending()).clips;

      expect(clips[0].url.path, '/small/100w.mp4');
      expect((clips[0].width, clips[0].height), (100, 50));
      expect(clips[1].url.path, '/gifonly/200w.gif');
    });

    test('leaves out a clip it cannot play or size', () async {
      final client = _client(
        (_) async => http.Response(
          _page([
            _clipJson('noimages', images: {}),
            _clipJson(
              'badsize',
              images: {
                'fixed_width': {
                  'mp4': 'https://media.example/b.mp4',
                  'width': '0',
                  'height': 'x',
                },
              },
            ),
            '"not an object"',
            _clipJson('ok'),
          ]),
          200,
        ),
      );

      final page = await client.trending();

      expect(page.clips.map((clip) => clip.id), ['ok']);
    });

    test(
      'names the next offset while there is more, and none at the end',
      () async {
        var total = 100;
        final client = _client(
          (request) async => http.Response(
            _page(
              [_clipJson('a'), _clipJson('b')],
              total: total,
              offset: int.parse(request.url.queryParameters['offset']!),
            ),
            200,
          ),
        );

        expect((await client.trending(offset: 10)).nextOffset, 12);
        total = 12;
        expect((await client.trending(offset: 10)).nextOffset, isNull);
      },
    );

    test('names no next offset for an empty page', () async {
      final client = _client(
        (_) async => http.Response(_page([], total: 100), 200),
      );

      expect((await client.trending()).nextOffset, isNull);
    });
  });

  group('search', () {
    test('sends the query and the offset', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response(_page([]), 200);
      });

      await client.search('happy cat', offset: 24);

      expect(seen.url.path, '/v1/gifs/search');
      expect(seen.url.queryParameters['q'], 'happy cat');
      expect(seen.url.queryParameters['offset'], '24');
    });
  });

  group('byIds', () {
    test('asks for the ids in one request', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response(_page([_clipJson('a'), _clipJson('b')]), 200);
      });

      final clips = await client.byIds(['a', 'b']);

      expect(seen.url.path, '/v1/gifs');
      expect(seen.url.queryParameters['ids'], 'a,b');
      expect(clips.map((clip) => clip.id), ['a', 'b']);
    });

    test('asks for nothing when given no id', () async {
      var asked = false;
      final client = _client((_) async {
        asked = true;
        return http.Response(_page([]), 200);
      });

      expect(await client.byIds([]), isEmpty);
      expect(asked, isFalse);
    });
  });

  group('download', () {
    test('returns the bytes, without the key', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response.bytes([1, 2, 3], 200);
      });

      final bytes = await client.download(
        Uri.parse('https://media.example/a.mp4'),
      );

      expect(bytes, Uint8List.fromList([1, 2, 3]));
      expect(seen.url.queryParameters.containsKey('api_key'), isFalse);
    });
  });

  group('failures', () {
    Future<GiphyFailure> failureOf(
      GiphyClient client,
      Future<Object?> Function(GiphyClient client) call,
    ) async {
      try {
        await call(client);
      } on GiphyFailure catch (failure) {
        return failure;
      }
      fail('did not fail');
    }

    test('are transient for a busy server and a limit', () async {
      for (final status in [429, 500, 503]) {
        final client = _client((_) async => http.Response('', status));
        final failure = await failureOf(client, (c) => c.trending());
        expect(failure.transient, isTrue, reason: '$status');
      }
    });

    test('are permanent for a refused key and a missing clip', () async {
      for (final status in [401, 403, 404]) {
        final client = _client((_) async => http.Response('', status));
        final failure = await failureOf(
          client,
          (c) => c.download(Uri.parse('https://media.example/a.mp4')),
        );
        expect(failure.transient, isFalse, reason: '$status');
      }
    });

    test('are transient for no network and for a timeout', () async {
      final offline = _client((_) async => throw http.ClientException('down'));
      final slow = _client(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      );

      expect((await failureOf(offline, (c) => c.trending())).transient, isTrue);
      expect((await failureOf(slow, (c) => c.trending())).transient, isTrue);
    });

    test(
      'are permanent for an answer that is not the documented shape',
      () async {
        final client = _client((_) async => http.Response('<html>', 200));

        expect(
          (await failureOf(client, (c) => c.trending())).transient,
          isFalse,
        );
      },
    );

    test('never carry the key', () async {
      final client = _client((_) async => http.Response('', 500));

      final failure = await failureOf(client, (c) => c.search('cat'));

      expect(failure.toString(), isNot(contains('secret-key')));
    });
  });
}
