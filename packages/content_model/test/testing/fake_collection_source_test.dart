import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _paged = CollectionId.category('people');
const _single = CollectionId.set('one-page');

List<CollectionItem> _items(Iterable<String> ids) => [
  for (final id in ids) CollectionItem.bare(ContentKey.document(id)),
];

FakeCollectionSource _source() => FakeCollectionSource([
  FakeCollectionSpec(
    _paged,
    metadata: const CollectionMetadata(title: 'People'),
    pages: FakePages([
      _items(['1', '2']),
      _items(['3']),
      _items(['4', '5']),
    ]),
  ),
  FakeCollectionSpec(
    _single,
    pages: FakePages([
      _items(['9']),
    ]),
  ),
  const FakeCollectionSpec(CollectionId.recent),
]);

void main() {
  CollectionSourceContract.run(() async {
    final source = _source();
    return CollectionSourceHarness(
      source: source,
      pagedId: _paged,
      missingId: const CollectionId.set('nope'),
      failLoads: ({required failing}) => source.failLoads = failing,
      failPages: ({required failing}) => source.failPages = failing,
    );
  });

  group('FakeCollectionSource', () {
    late FakeCollectionSource source;

    Collection collection(CollectionId id) =>
        source.collections.value.firstWhere((c) => c.id == id);

    setUp(() => source = _source());

    tearDown(() => source.dispose());

    test('lists the specs in order with their metadata', () {
      expect(
        [for (final c in source.collections.value) c.id],
        [_paged, _single, CollectionId.recent],
      );
      expect(collection(_paged).metadata.title, 'People');
    });

    test('serves the pages in order, ending without a token', () async {
      await source.load(_paged);
      await source.loadMore(_paged);
      await source.loadMore(_paged);

      expect(
        collection(_paged).contents,
        CollectionContents.loaded(_items(['1', '2', '3', '4', '5'])),
      );
    });

    test('loads a collection without pages as loaded and empty', () async {
      await source.load(CollectionId.recent);

      expect(
        collection(CollectionId.recent).contents,
        CollectionContents.loaded(const []),
      );
    });

    test('holds work in flight while paused', () async {
      source.pause();
      final pending = source.load(_paged);

      await Future<void>.delayed(Duration.zero);
      expect(collection(_paged).contents, CollectionContents.loading);

      source.resume();
      await pending;
      expect(collection(_paged).contents, isA<CollectionContents$Loaded>());
    });

    test('ignores load while the collection is loading', () async {
      source.pause();
      final first = source.load(_paged);
      final second = source.load(_paged);
      source.resume();
      await Future.wait([first, second]);

      expect(collection(_paged).contents, isA<CollectionContents$Loaded>());
    });
  });
}
