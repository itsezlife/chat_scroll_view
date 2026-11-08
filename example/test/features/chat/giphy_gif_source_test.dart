/// The Giphy sources of the GIF page: trending as a collection, search as
/// results.
///
/// **Seam:** [GiphyGifSource] and [GiphyGifSearch] over a [GiphyClient] with a
/// fake `http.Client`, run against the seam contracts of `content_model`, plus
/// what is theirs: the offsets they ask for, the clips they remember, no key
/// twice.
library;

import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';

import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_gif_source.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A fake Giphy of 6 clips per feed, 2 to a page, as hand-written JSON. A clip
// of the feed with prefix `p` at position `n` is `p<n>`; `overlap` makes each
// page repeat the last clip of the one before. Each clip has a still at
// `https://media.example/<id>.still.gif`, held while [stillGate] is.
final class _FakeGiphy {
  bool failFirst = false;
  bool failLater = false;
  bool overlap = false;
  final List<Uri> requests = <Uri>[];
  // The still files answered, in order: a still is here once its bytes went
  // back to the client.
  final List<String> stillsServed = <String>[];
  Completer<void>? gate;
  Completer<void>? stillGate;

  List<Uri> get apiRequests => [
    for (final url in requests)
      if (url.host == 'api.giphy.com') url,
  ];

  http.Client get client => MockClient((request) async {
    requests.add(request.url);
    if (request.url.host == 'media.example') {
      await stillGate?.future;
      stillsServed.add(request.url.path);
      return http.Response.bytes([1, 2, 3], 200);
    }
    await gate?.future;
    final offset = int.parse(request.url.queryParameters['offset']!);
    if (offset == 0 ? failFirst : failLater) return http.Response('', 503);
    final prefix = switch (request.url.path) {
      '/v1/gifs/trending' => 't',
      _ => request.url.queryParameters['q']![0],
    };
    final ids = [
      for (var n = offset; n < offset + 2; n++)
        if (overlap && n > 0 && n == offset) '$prefix${n - 1}' else '$prefix$n',
    ];
    final data = [
      for (final id in ids)
        '{"id":"$id","title":"$id","images":{"fixed_width":'
            '{"mp4":"https://media.example/$id.mp4","width":"200","height":"100"},'
            '"fixed_width_small_still":{"url":"https://media.example/$id.still.gif"}}}',
    ].join(',');
    return http.Response(
      '{"data":[$data],"pagination":{"total_count":6,"count":2,"offset":$offset}}',
      200,
    );
  });
}

void main() {
  late _FakeGiphy giphy;
  late GiphyClient client;
  late GiphyContent content;

  setUp(() {
    giphy = _FakeGiphy();
    client = GiphyClient(apiKey: 'k', client: giphy.client, pageSize: 2);
    content = GiphyContent(client);
  });

  List<String> idsOf(Collection collection) => [
    for (final item in (collection.contents as CollectionContents$Loaded).items)
      item.key.encoded,
  ];

  group('trending', () {
    CollectionSourceContract.run(() async {
      final giphy = _FakeGiphy();
      final client = GiphyClient(
        apiKey: 'k',
        client: giphy.client,
        pageSize: 2,
      );
      return CollectionSourceHarness(
        source: GiphyGifSource(client: client, content: GiphyContent(client)),
        pagedId: GiphyGifSource.id,
        missingId: const CollectionId.set('nope'),
        failLoads: ({required failing}) => giphy.failFirst = failing,
        failPages: ({required failing}) => giphy.failLater = failing,
      );
    });

    test('is idle until the page asks, and asks nothing before', () {
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);

      expect(source.collections.value.single.contents, CollectionContents.idle);
      expect(giphy.requests, isEmpty);
    });

    test('pages by the offset the last page named', () async {
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);

      await source.load(GiphyGifSource.id);
      await source.loadMore(GiphyGifSource.id);
      await source.loadMore(GiphyGifSource.id);
      await source.loadMore(GiphyGifSource.id);

      expect(giphy.apiRequests.map((u) => u.queryParameters['offset']), [
        '0',
        '2',
        '4',
      ]);
      expect(idsOf(source.collections.value.single), [
        for (var n = 0; n < 6; n++) 'document:giphy:t$n',
      ]);
    });

    test('lists a clip once however many pages repeat it', () async {
      giphy.overlap = true;
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);

      await source.load(GiphyGifSource.id);
      await source.loadMore(GiphyGifSource.id);

      expect(idsOf(source.collections.value.single), [
        'document:giphy:t0',
        'document:giphy:t1',
        'document:giphy:t3',
      ]);
    });

    test('remembers the clips, so the pipeline can play them', () async {
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);

      await source.load(GiphyGifSource.id);

      expect(content.clipOf(GiphyContent.keyOf('t1'))?.width, 200);
    });

    test(
      'describes each item, so a row has its proportions before it plays',
      () async {
        final source = GiphyGifSource(client: client, content: content);
        addTearDown(source.dispose);

        await source.load(GiphyGifSource.id);

        final item =
            (source.collections.value.single.contents
                    as CollectionContents$Loaded)
                .items
                .first;
        expect(item.descriptor?.size, const ContentSize(200, 100));
        expect(item.descriptor?.mediaForm, MediaForm.video);
      },
    );
  });

  group('the stills', () {
    test('are fetched before the rows that show them are added', () async {
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);
      final servedWhenAdded = <List<String>>[];
      source.collections.addListener(() {
        if (source.collections.value.single.contents
            is CollectionContents$Loaded) {
          servedWhenAdded.add([...giphy.stillsServed]);
        }
      });

      await source.load(GiphyGifSource.id);

      expect(
        servedWhenAdded.first,
        containsAll(['/t0.still.gif', '/t1.still.gif']),
      );
    });

    test('a still later than the wait does not hold the rows back', () async {
      giphy.stillGate = Completer<void>();
      final source = GiphyGifSource(
        client: client,
        content: content,
        stillWait: const Duration(milliseconds: 20),
      );
      addTearDown(source.dispose);

      await source.load(GiphyGifSource.id);

      expect(idsOf(source.collections.value.single), [
        'document:giphy:t0',
        'document:giphy:t1',
      ]);
      expect(giphy.stillsServed, isEmpty);
      giphy.stillGate!.complete();
    });

    test('are the thumbnails the fetcher gives, without a request', () async {
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);
      await source.load(GiphyGifSource.id);
      final item =
          (source.collections.value.single.contents
                  as CollectionContents$Loaded)
              .items
              .first;
      final before = giphy.requests.length;

      final fetched = await content
          .fetcher(otherwise: _Unused())
          .fetch(
            FetchRequest(
              descriptor: item.descriptor!,
              part: FetchPart.thumbnail,
              priority: AssetPriority.placeholder,
              cancellation: CancellationToken(),
            ),
          );

      expect((fetched as FetchedBytes).bytes, [1, 2, 3]);
      expect(giphy.requests.length, before);
    });
  });

  group('the next page', () {
    test('is fetched, stills too, while the current one shows', () async {
      final source = GiphyGifSource(client: client, content: content);
      addTearDown(source.dispose);

      await source.load(GiphyGifSource.id);
      await pumpEventQueue();

      expect(giphy.apiRequests.map((u) => u.queryParameters['offset']), [
        '0',
        '2',
      ]);
      expect(
        giphy.stillsServed,
        containsAll(['/t2.still.gif', '/t3.still.gif']),
      );
      // Still not listed: the page has not asked for it.
      expect(idsOf(source.collections.value.single), hasLength(2));
    });

    test(
      'is added from what was fetched ahead, without asking again',
      () async {
        final source = GiphyGifSource(client: client, content: content);
        addTearDown(source.dispose);
        await source.load(GiphyGifSource.id);
        await pumpEventQueue();

        giphy.gate = Completer<void>();
        await source.loadMore(GiphyGifSource.id);

        expect(idsOf(source.collections.value.single), [
          for (var n = 0; n < 4; n++) 'document:giphy:t$n',
        ]);
        giphy.gate!.complete();
      },
    );

    test('is fetched ahead for search results too', () async {
      final search = GiphyGifSearch(client: client, content: content);
      addTearDown(search.dispose);

      await search.search('cat');
      await pumpEventQueue();

      expect(giphy.apiRequests.map((u) => u.queryParameters['offset']), [
        '0',
        '2',
      ]);
    });
  });

  group('search', () {
    SearchSourceContract.run(() async {
      final giphy = _FakeGiphy();
      final client = GiphyClient(
        apiKey: 'k',
        client: giphy.client,
        pageSize: 2,
      );
      return SearchSourceHarness(
        source: GiphyGifSearch(client: client, content: GiphyContent(client)),
        query: 'cat',
        otherQuery: 'dog',
        failSearches: ({required failing}) => giphy.failFirst = failing,
        failPages: ({required failing}) => giphy.failLater = failing,
      );
    });

    test('sends the query and pages by offset', () async {
      final search = GiphyGifSearch(client: client, content: content);
      addTearDown(search.dispose);

      await search.search('cat');
      await search.loadMore();

      expect(giphy.apiRequests.map((u) => u.queryParameters['q']), [
        'cat',
        'cat',
      ]);
      expect(giphy.apiRequests.map((u) => u.queryParameters['offset']), [
        '0',
        '2',
      ]);
    });

    test('answers a query it found before from memory', () async {
      final search = GiphyGifSearch(client: client, content: content);
      addTearDown(search.dispose);
      await search.search('cat');
      final found = search.results.value;
      await search.search('dog');
      final asked = giphy.apiRequests.length;

      await search.search('cat');

      expect(giphy.apiRequests, hasLength(asked));
      expect(search.results.value.id, const CollectionId.query('cat'));
      expect(idsOf(search.results.value), idsOf(found));
    });

    test('asks again for a query that failed', () async {
      final search = GiphyGifSearch(client: client, content: content);
      addTearDown(search.dispose);
      giphy.failFirst = true;
      await search.search('cat');
      giphy.failFirst = false;
      await search.search('dog');

      await search.search('cat');

      expect(idsOf(search.results.value), [
        'document:giphy:c0',
        'document:giphy:c1',
      ]);
    });

    test(
      'a query left before its reply is not published when it lands',
      () async {
        final search = GiphyGifSearch(client: client, content: content);
        addTearDown(search.dispose);
        giphy.gate = Completer<void>();
        final cat = search.search('cat');
        final dog = search.search('dog');

        giphy.gate!.complete();
        await (cat, dog).wait;

        expect(search.results.value.id, const CollectionId.query('dog'));
        expect(idsOf(search.results.value), [
          'document:giphy:d0',
          'document:giphy:d1',
        ]);
      },
    );

    test('asks nothing for blank text', () async {
      final search = GiphyGifSearch(client: client, content: content);
      addTearDown(search.dispose);

      await search.search('   ');

      expect(giphy.requests, isEmpty);
    });
  });
}

// The fetcher every other key would go to: these tests ask only for Giphy's.
final class _Unused implements ContentFetcher {
  @override
  Future<FetchedContent> fetch(FetchRequest request) =>
      throw StateError('not a Giphy key: ${request.descriptor.key}');
}
