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
import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

GiphyClip _clip(String id, {String title = 'a cat', bool still = false}) =>
    GiphyClip(
      id: id,
      title: title,
      url: Uri.parse('https://media.example/$id.mp4'),
      width: 200,
      height: 100,
      thumbnailUrl: still
          ? Uri.parse('https://media.example/$id.still.gif')
          : null,
    );

FetchRequest _request(
  ContentKey key, {
  FetchPart part = FetchPart.content,
  FetchProgress? onProgress,
}) => FetchRequest(
  descriptor: ContentDescriptor(key: key),
  part: part,
  priority: AssetPriority.visible,
  cancellation: CancellationToken(),
  onProgress: onProgress ?? (_, _) {},
);

const _otherMissing = ContentKey.document('elsewhere');

final class _Other implements ContentFetcher, ContentResolver {
  final fetched = <ContentKey>[];
  final resolved = <ContentKey>[];

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    fetched.add(request.descriptor.key);
    return FetchedContent.bytes(Uint8List.fromList([9]));
  }

  @override
  bool needsDownload(ContentKey key) => key == _otherMissing;

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
  late GiphyClient client;
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
    client = GiphyClient(
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

    test('names the still of the clip as its thumbnail, when it has one', () {
      expect(content.describe(_clip('abc')).thumbnail, isNull);
      expect(
        content.describe(_clip('abc', still: true)).thumbnail,
        const ThumbnailRef('https://media.example/abc.still.gif'),
      );
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

    test('reports the download of the clip to the fetch', () async {
      files['/a.mp4'] = Uint8List.fromList([1, 2, 3]);
      content.remember([_clip('a')]);
      final reports = <(int, int?)>[];

      await content
          .fetcher(otherwise: other)
          .fetch(
            _request(
              GiphyContent.keyOf('a'),
              onProgress: (received, total) => reports.add((received, total)),
            ),
          );

      expect(reports.first, (0, 3));
      expect(reports.last, (3, 3));
    });

    test('reports one download to every fetch that shares it', () async {
      files['/a.mp4'] = Uint8List.fromList([1, 2]);
      content.remember([_clip('a')]);
      gate = Completer<void>();
      final fetcher = content.fetcher(otherwise: other);
      final first = <(int, int?)>[];
      final second = <(int, int?)>[];

      final one = fetcher.fetch(
        _request(
          GiphyContent.keyOf('a'),
          onProgress: (received, total) => first.add((received, total)),
        ),
      );
      final two = fetcher.fetch(
        _request(
          GiphyContent.keyOf('a'),
          onProgress: (received, total) => second.add((received, total)),
        ),
      );
      await pumpEventQueue();
      gate!.complete();
      await Future.wait([one, two]);

      expect(first.last, (2, 2));
      expect(second.last, (2, 2));
    });

    test('a fetch that joins a running download hears where it is', () async {
      final body = StreamController<List<int>>();
      final streaming = GiphyContent(
        GiphyClient(
          apiKey: 'k',
          client: MockClient.streaming(
            (_, _) async =>
                http.StreamedResponse(body.stream, 200, contentLength: 4),
          ),
        ),
      )..remember([_clip('a')]);
      final fetcher = streaming.fetcher(otherwise: other);
      final one = fetcher.fetch(_request(GiphyContent.keyOf('a')));
      body.add([1, 2]);
      await pumpEventQueue();
      final late = <(int, int?)>[];

      final two = fetcher.fetch(
        _request(
          GiphyContent.keyOf('a'),
          onProgress: (received, total) => late.add((received, total)),
        ),
      );
      body.add([3, 4]);
      await body.close();
      await Future.wait([one, two]);

      expect(late, [(2, 4), (4, 4)]);
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

    test(
      'downloads the still named by the descriptor as the thumbnail',
      () async {
        final clip = _clip('a', still: true);
        content.remember([clip]);
        files['/a.still.gif'] = Uint8List.fromList([7, 7]);
        final request = FetchRequest(
          descriptor: content.describe(clip),
          part: FetchPart.thumbnail,
          priority: AssetPriority.placeholder,
          cancellation: CancellationToken(),
        );

        final fetched = await content.fetcher(otherwise: other).fetch(request);

        expect((fetched as FetchedBytes).bytes, [7, 7]);
        // Not the clip's file, and not an API request.
        expect(requests.map((r) => r.url.path), ['/a.still.gif']);
      },
    );

    test('a thumbnail of a failing still is a failure of its own', () async {
      final clip = _clip('a', still: true);
      content.remember([clip]);
      final request = FetchRequest(
        descriptor: content.describe(clip),
        part: FetchPart.thumbnail,
        priority: AssetPriority.placeholder,
        cancellation: CancellationToken(),
      );

      await expectLater(
        content.fetcher(otherwise: other).fetch(request),
        throwsA(isA<FetchFailure>()),
      );
    });

    test('has no thumbnail to give when the descriptor names none', () async {
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

  group('the stills', () {
    FetchRequest still(
      GiphyContent from,
      GiphyClip clip, {
      FetchProgress? onProgress,
    }) => FetchRequest(
      descriptor: from.describe(clip),
      part: FetchPart.thumbnail,
      priority: AssetPriority.placeholder,
      cancellation: CancellationToken(),
      onProgress: onProgress ?? (_, _) {},
    );

    test('report their download, and none from memory', () async {
      final clip = _clip('a', still: true);
      files['/a.still.gif'] = Uint8List.fromList([7, 7]);
      final fetcher = content.fetcher(otherwise: other);
      final first = <(int, int?)>[];
      final again = <(int, int?)>[];

      await fetcher.fetch(
        still(
          content,
          clip,
          onProgress: (received, total) => first.add((received, total)),
        ),
      );
      await fetcher.fetch(
        still(
          content,
          clip,
          onProgress: (received, total) => again.add((received, total)),
        ),
      );

      expect(first, [(0, 2), (2, 2)]);
      expect(again, isEmpty);
    });

    test('are given again from memory without a request', () async {
      final clip = _clip('a', still: true);
      files['/a.still.gif'] = Uint8List.fromList([7]);
      final fetcher = content.fetcher(otherwise: other);

      await fetcher.fetch(still(content, clip));
      final again = await fetcher.fetch(still(content, clip));

      expect((again as FetchedBytes).bytes, [7]);
      expect(requests, hasLength(1));
    });

    test('are found on disk by a later session, without a request', () async {
      final disk = _MemoryDisk();
      final clip = _clip('a', still: true);
      files['/a.still.gif'] = Uint8List.fromList([7]);
      final first = GiphyContent(client, stillDisk: disk);
      await first.fetcher(otherwise: other).fetch(still(first, clip));
      requests.clear();

      final later = GiphyContent(client, stillDisk: disk);
      final fetched = await later
          .fetcher(otherwise: other)
          .fetch(still(later, clip));

      expect((fetched as FetchedBytes).bytes, [7]);
      expect(requests, isEmpty);
    });

    test('are kept under the clip, whatever URL Giphy gives next', () async {
      final disk = _MemoryDisk();
      files['/a.still.gif'] = Uint8List.fromList([7]);
      final first = GiphyContent(client, stillDisk: disk);
      await first
          .fetcher(otherwise: other)
          .fetch(still(first, _clip('a', still: true)));
      requests.clear();

      // The same still under another answer's URL.
      final retagged = GiphyClip(
        id: 'a',
        title: 'a cat',
        url: Uri.parse('https://media.example/a.mp4'),
        width: 200,
        height: 100,
        thumbnailUrl: Uri.parse('https://media.example/a.still.gif?cid=2'),
      );
      final later = GiphyContent(client, stillDisk: disk);
      await later.fetcher(otherwise: other).fetch(still(later, retagged));

      expect(requests, isEmpty);
    });

    test('are prepared ahead, so the fetcher asks for nothing', () async {
      final clips = [_clip('a', still: true), _clip('b', still: true)];
      files['/a.still.gif'] = Uint8List.fromList([1]);
      files['/b.still.gif'] = Uint8List.fromList([2]);

      await content.prepareStills(clips, within: const Duration(seconds: 1));
      requests.clear();
      final fetcher = content.fetcher(otherwise: other);
      for (final clip in clips) {
        await fetcher.fetch(still(content, clip));
      }

      expect(requests, isEmpty);
    });

    test('a still that fails to prepare is no failure of the wait', () async {
      await content.prepareStills([
        _clip('gone', still: true),
      ], within: const Duration(seconds: 1));

      expect(requests.single.url.path, '/gone.still.gif');
    });
  });

  group('the clips', () {
    test('are found on disk by a later session, without a request, even '
        'one it never listed', () async {
      final disk = _MemoryDisk();
      files['/a.mp4'] = Uint8List.fromList([1, 2]);
      final first = GiphyContent(client, clipDisk: disk)
        ..remember([_clip('a')]);
      await first
          .fetcher(otherwise: other)
          .fetch(_request(GiphyContent.keyOf('a')));
      await pumpEventQueue();
      requests.clear();

      final later = GiphyContent(client, clipDisk: disk);
      final fetched = await later
          .fetcher(otherwise: other)
          .fetch(_request(GiphyContent.keyOf('a')));

      expect((fetched as FetchedBytes).bytes, [1, 2]);
      expect(requests, isEmpty);
    });

    test('found on disk report no download', () async {
      final disk = _MemoryDisk();
      await disk.write('clip_a', Uint8List.fromList([1, 2]));
      final content = GiphyContent(client, clipDisk: disk);
      final reports = <(int, int?)>[];

      await content
          .fetcher(otherwise: other)
          .fetch(
            _request(
              GiphyContent.keyOf('a'),
              onProgress: (received, total) => reports.add((received, total)),
            ),
          );

      expect(reports, isEmpty);
    });

    test('are known to need a download unless the disk has them', () async {
      final disk = _MemoryDisk();
      await disk.write('clip_a', Uint8List.fromList([1, 2]));
      final fetcher = GiphyContent(
        client,
        clipDisk: disk,
      ).fetcher(otherwise: other);

      expect(fetcher.needsDownload(GiphyContent.keyOf('a')), isFalse);
      expect(fetcher.needsDownload(GiphyContent.keyOf('b')), isTrue);
    });

    test('need a download without a disk, and for other content the fetcher '
        'given says', () {
      final fetcher = GiphyContent(client).fetcher(otherwise: other);

      expect(fetcher.needsDownload(GiphyContent.keyOf('a')), isTrue);
      expect(fetcher.needsDownload(_otherMissing), isTrue);
      expect(
        fetcher.needsDownload(const ContentKey.document('bundled')),
        isFalse,
      );
    });

    test('are downloaded and kept when the disk has none', () async {
      final disk = _MemoryDisk();
      files['/a.mp4'] = Uint8List.fromList([3]);
      final content = GiphyContent(client, clipDisk: disk)
        ..remember([_clip('a')]);

      await content
          .fetcher(otherwise: other)
          .fetch(_request(GiphyContent.keyOf('a')));
      await pumpEventQueue();

      expect(requests.single.url.path, '/a.mp4');
      expect(await disk.read('clip_a'), [3]);
    });

    test('are not mixed with the stills on one disk', () async {
      final disk = _MemoryDisk();
      files['/a.mp4'] = Uint8List.fromList([1]);
      files['/a.still.gif'] = Uint8List.fromList([7]);
      final clip = _clip('a', still: true);
      final content = GiphyContent(client, stillDisk: disk, clipDisk: disk)
        ..remember([clip]);
      final fetcher = content.fetcher(otherwise: other);

      await fetcher.fetch(_request(GiphyContent.keyOf('a')));
      final still = await fetcher.fetch(
        FetchRequest(
          descriptor: content.describe(clip),
          part: FetchPart.thumbnail,
          priority: AssetPriority.placeholder,
          cancellation: CancellationToken(),
        ),
      );

      expect((still as FetchedBytes).bytes, [7]);
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

// A disk tier in memory: what a later session over the same folder reads.
final class _MemoryDisk implements ByteCache {
  final Map<String, Uint8List> _files = {};

  @override
  Future<Uint8List?> read(String name) async => _files[name];

  @override
  bool holds(String name) => _files.containsKey(name);

  @override
  Future<void> write(String name, Uint8List bytes) async =>
      _files[name] = bytes;
}
