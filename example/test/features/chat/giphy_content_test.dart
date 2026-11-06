/// Giphy clips as content of the asset pipeline: their identity, descriptors,
/// fetching and resolving.
///
/// **Seam:** [GiphyContent] with a [GiphyClient] over a fake `http.Client`,
/// observed through the `ContentFetcher` and `ContentResolver` it makes and
/// the requests the fake saw.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

GiphyClip _clip(String id, {String title = 'a cat'}) => GiphyClip(
  id: id,
  title: title,
  url: Uri.parse('https://media.example/$id.mp4'),
  width: 200,
  height: 100,
);

FetchRequest _request(ContentKey key, {FetchPart part = FetchPart.content}) =>
    FetchRequest(
      descriptor: ContentDescriptor(key: key),
      part: part,
      priority: AssetPriority.visible,
      cancellation: CancellationToken(),
    );

final class _Other implements ContentFetcher, ContentResolver {
  final fetched = <ContentKey>[];
  final resolved = <ContentKey>[];

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    fetched.add(request.descriptor.key);
    return FetchedContent.bytes(Uint8List.fromList([9]));
  }

  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async {
    resolved.addAll(keys);
    return {for (final key in keys) key: ContentDescriptor(key: key)};
  }
}

void main() {
  late List<http.Request> requests;
  late Map<String, Uint8List> files;
  late Map<String, GiphyClip> known;
  late Completer<void>? gate;
  late GiphyContent content;
  late _Other other;
  var failApi = false;

  setUp(() {
    requests = [];
    files = {};
    known = {};
    gate = null;
    failApi = false;
    other = _Other();
    final client = GiphyClient(
      apiKey: 'k',
      client: MockClient((request) async {
        requests.add(request);
        if (failApi) return http.Response('', 503);
        if (request.url.host == 'api.giphy.com') {
          final ids = request.url.queryParameters['ids']!.split(',');
          final clips = [for (final id in ids) ?known[id]];
          return http.Response(
            '{"data":[${[for (final clip in clips) '{"id":"${clip.id}","title":"${clip.title}",'
                  '"images":{"fixed_width":{"mp4":"${clip.url}",'
                  '"width":"${clip.width}","height":"${clip.height}"}}}'].join(',')}]}',
            200,
          );
        }
        await gate?.future;
        final bytes = files[request.url.path];
        return bytes == null
            ? http.Response('', 404)
            : http.Response.bytes(bytes, 200);
      }),
    );
    content = GiphyContent(client, capacity: 3);
  });

  group('the key', () {
    test('is a document under the Giphy prefix and reads back its id', () {
      final key = GiphyContent.keyOf('abc');

      expect(key, const ContentKey.document('giphy:abc'));
      expect(GiphyContent.isKey(key), isTrue);
      expect(GiphyContent.idOf(key), 'abc');
    });

    test('is not any other content', () {
      for (final key in [
        const ContentKey.document('demo-video:orbit'),
        const ContentKey.unicode('\u{1F600}'),
      ]) {
        expect(GiphyContent.isKey(key), isFalse);
        expect(GiphyContent.idOf(key), isNull);
      }
    });
  });

  group('the descriptor', () {
    test('says a gif the video decoder plays, as large as the file', () {
      final descriptor = content.describe(_clip('abc'));

      expect(descriptor.key, GiphyContent.keyOf('abc'));
      expect(descriptor.semanticKind, SemanticKind.gif);
      expect(descriptor.mediaForm, MediaForm.video);
      expect(descriptor.animated, isTrue);
      expect(descriptor.size, const ContentSize(200, 100));
      expect(descriptor.spokenName, 'a cat');
    });

    test('is spoken as a GIF when the clip has no title', () {
      expect(content.describe(_clip('abc', title: '')).spokenName, 'GIF');
    });
  });

  group('what it remembers', () {
    test('is the clips it was told, up to its capacity, oldest used first', () {
      content.remember([_clip('a'), _clip('b'), _clip('c')]);
      content.clipOf(GiphyContent.keyOf('a'));
      content.remember([_clip('d')]);

      expect(content.clipOf(GiphyContent.keyOf('a')), isNotNull);
      expect(content.clipOf(GiphyContent.keyOf('b')), isNull);
      expect(content.descriptorOf(GiphyContent.keyOf('d')), isNotNull);
    });
  });

  group('the fetcher', () {
    test('downloads the file of a remembered clip', () async {
      files['/a.mp4'] = Uint8List.fromList([1, 2, 3]);
      content.remember([_clip('a')]);

      final fetched = await content
          .fetcher(otherwise: other)
          .fetch(_request(GiphyContent.keyOf('a')));

      expect((fetched as FetchedBytes).bytes, [1, 2, 3]);
      expect(requests.single.url.host, 'media.example');
    });

    test(
      'asks Giphy for a clip it does not remember, as after a restart',
      () async {
        files['/a.mp4'] = Uint8List.fromList([1]);
        known['a'] = _clip('a');

        final fetched = await content
            .fetcher(otherwise: other)
            .fetch(_request(GiphyContent.keyOf('a')));

        expect((fetched as FetchedBytes).bytes, [1]);
        expect(requests.first.url.queryParameters['ids'], 'a');
      },
    );

    test('fails a clip Giphy does not know for good', () async {
      await expectLater(
        content
            .fetcher(otherwise: other)
            .fetch(_request(GiphyContent.keyOf('gone'))),
        throwsA(
          isA<FetchFailure>().having(
            (failure) => failure.kind,
            'kind',
            AssetFailureKind.permanent,
          ),
        ),
      );
    });

    test('fails offline as something connectivity can fix', () async {
      final client = GiphyClient(
        apiKey: 'k',
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      final offline = GiphyContent(client)..remember([_clip('a')]);

      await expectLater(
        offline
            .fetcher(otherwise: other)
            .fetch(_request(GiphyContent.keyOf('a'))),
        throwsA(
          isA<FetchFailure>().having(
            (failure) => failure.kind,
            'kind',
            AssetFailureKind.transient,
          ),
        ),
      );
    });

    test('downloads once for fetches that overlap', () async {
      files['/a.mp4'] = Uint8List.fromList([1]);
      content.remember([_clip('a')]);
      gate = Completer<void>();
      final fetcher = content.fetcher(otherwise: other);

      final first = fetcher.fetch(_request(GiphyContent.keyOf('a')));
      final second = fetcher.fetch(_request(GiphyContent.keyOf('a')));
      await pumpEventQueue();
      gate!.complete();
      await Future.wait([first, second]);

      expect(
        requests.where((r) => r.url.host == 'media.example'),
        hasLength(1),
      );
    });

    test('downloads again once the first has finished', () async {
      files['/a.mp4'] = Uint8List.fromList([1]);
      content.remember([_clip('a')]);
      final fetcher = content.fetcher(otherwise: other);

      await fetcher.fetch(_request(GiphyContent.keyOf('a')));
      await fetcher.fetch(_request(GiphyContent.keyOf('a')));

      expect(
        requests.where((r) => r.url.host == 'media.example'),
        hasLength(2),
      );
    });

    test('has no thumbnail to give', () async {
      content.remember([_clip('a')]);

      await expectLater(
        content
            .fetcher(otherwise: other)
            .fetch(
              _request(GiphyContent.keyOf('a'), part: FetchPart.thumbnail),
            ),
        throwsA(isA<FetchFailure>()),
      );
    });

    test('leaves other content to the fetcher it was given', () async {
      const key = ContentKey.document('demo-video:orbit');

      await content.fetcher(otherwise: other).fetch(_request(key));

      expect(other.fetched, [key]);
      expect(requests, isEmpty);
    });
  });

  group('the resolver', () {
    test('describes remembered clips without a request', () async {
      content.remember([_clip('a')]);

      final found = await content.resolver(otherwise: other).resolve([
        GiphyContent.keyOf('a'),
      ]);

      expect(found[GiphyContent.keyOf('a')]?.size, const ContentSize(200, 100));
      expect(requests, isEmpty);
    });

    test(
      'asks Giphy once for the clips it does not remember, and keeps them',
      () async {
        known['a'] = _clip('a');
        known['b'] = _clip('b');
        final resolver = content.resolver(otherwise: other);

        final found = await resolver.resolve([
          GiphyContent.keyOf('a'),
          GiphyContent.keyOf('b'),
          GiphyContent.keyOf('unknown'),
        ]);

        expect(found.keys, {GiphyContent.keyOf('a'), GiphyContent.keyOf('b')});
        expect(requests, hasLength(1));
        expect(content.clipOf(GiphyContent.keyOf('a')), isNotNull);
      },
    );

    test('hands other keys on, and only those', () async {
      known['a'] = _clip('a');
      const bundled = ContentKey.document('demo-video:orbit');

      final found = await content.resolver(otherwise: other).resolve([
        GiphyContent.keyOf('a'),
        bundled,
      ]);

      expect(other.resolved, [bundled]);
      expect(found.keys, {GiphyContent.keyOf('a'), bundled});
    });

    test('fails the batch when Giphy cannot be asked', () async {
      failApi = true;

      await expectLater(
        content.resolver(otherwise: other).resolve([GiphyContent.keyOf('a')]),
        throwsA(isA<GiphyFailure>()),
      );
    });
  });
}
