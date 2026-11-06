/// The Giphy sources of the GIF page: trending as a collection, search as
/// results.
///
/// **Seam:** [GiphyGifSource] and [GiphyGifSearch] over a [GiphyClient] with a
/// fake `http.Client`, run against the seam contracts of `content_model`, plus
/// what is theirs: the offsets they ask for, the clips they remember, no key
/// twice.
library;

import 'dart:async';

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
// page repeat the last clip of the one before.
final class _FakeGiphy {
  var failFirst = false;
  var failLater = false;
  var overlap = false;
  final requests = <Uri>[];
  Completer<void>? gate;

  http.Client get client => MockClient((request) async {
    requests.add(request.url);
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
            '{"mp4":"https://media.example/$id.mp4","width":"200","height":"100"}}}',
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

      expect(giphy.requests.map((u) => u.queryParameters['offset']), [
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

      expect(giphy.requests.map((u) => u.queryParameters['q']), ['cat', 'cat']);
      expect(giphy.requests.map((u) => u.queryParameters['offset']), [
        '0',
        '2',
      ]);
    });

    test('asks nothing for blank text', () async {
      final search = GiphyGifSearch(client: client, content: content);
      addTearDown(search.dispose);

      await search.search('   ');

      expect(giphy.requests, isEmpty);
    });
  });
}
