import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

List<CollectionItem> _items(Iterable<String> ids) => [
  for (final id in ids) CollectionItem.bare(ContentKey.document(id)),
];

FakeSearchSource _source() => FakeSearchSource({
  'cat': FakePages([
    _items(['1', '2']),
    _items(['3']),
    _items(['4']),
  ]),
  'dog': FakePages([
    _items(['7']),
  ]),
});

void main() {
  runSearchSourceContract(() async {
    final source = _source();
    return SearchSourceHarness(
      source: source,
      query: 'cat',
      otherQuery: 'dog',
      failSearches: ({required failing}) => source.failSearches = failing,
      failPages: ({required failing}) => source.failPages = failing,
    );
  });

  group('FakeSearchSource', () {
    late FakeSearchSource source;

    setUp(() => source = _source());

    tearDown(() => source.dispose());

    test('finds nothing for a query it was not scripted for', () async {
      await source.search('zebra');

      expect(
        source.results.value,
        Collection(
          id: const CollectionId.query('zebra'),
          contents: CollectionContents.loaded(const []),
        ),
      );
    });

    test('serves the scripted pages in order', () async {
      await source.search('cat');
      await source.loadMore();
      await source.loadMore();

      expect(
        source.results.value.contents,
        CollectionContents.loaded(_items(['1', '2', '3', '4'])),
      );
    });

    test('holds a search in flight while paused', () async {
      source.pause();
      final pending = source.search('cat');

      await Future<void>.delayed(Duration.zero);
      expect(source.results.value.contents, CollectionContents.loading);

      source.resume();
      await pending;
      expect(source.results.value.contents, isA<CollectionContents$Loaded>());
    });
  });
}
