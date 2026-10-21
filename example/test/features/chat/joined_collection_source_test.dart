import 'package:chat_scroll_view_example/src/features/chat/data/joined_collection_source.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const CollectionId _people = CollectionId.category('people');
const CollectionId _nature = CollectionId.category('nature');
const CollectionId _pack = CollectionId.set('pack');

FakePages _onePage(String id) => FakePages([
  [CollectionItem.bare(ContentKey.document(id))],
]);

void main() {
  late FakeCollectionSource catalogue;
  late FakeCollectionSource packs;
  late JoinedCollectionSource joined;

  setUp(() {
    catalogue = FakeCollectionSource([
      FakeCollectionSpec(_people, pages: _onePage('a')),
      FakeCollectionSpec(_nature, pages: _onePage('b')),
    ]);
    packs = FakeCollectionSource([
      FakeCollectionSpec(_pack, pages: _onePage('c')),
    ]);
    joined = JoinedCollectionSource([catalogue, packs]);
  });

  tearDown(() {
    joined.dispose();
    packs.dispose();
    catalogue.dispose();
  });

  List<CollectionId> ids() => [
    for (final collection in joined.collections.value) collection.id,
  ];

  test('lists the collections of every part, in the order of the parts', () {
    expect(ids(), [_people, _nature, _pack]);
  });

  test('sends a load to the part that lists the collection', () async {
    await joined.load(_pack);

    expect(
      packs.collections.value.single.contents,
      isA<CollectionContents$Loaded>(),
    );
    expect(
      catalogue.collections.value.map((collection) => collection.contents),
      everyElement(CollectionContents.idle),
    );
  });

  test('publishes a change of any part as one new joined list', () async {
    var signals = 0;
    joined.collections.addListener(() => signals++);

    await joined.load(_nature);

    expect(signals, greaterThan(0));
    expect(
      joined.collections.value[1].contents,
      isA<CollectionContents$Loaded>(),
    );
    expect(ids(), [_people, _nature, _pack]);
  });

  test('changes nothing for an id no part lists', () async {
    final before = joined.collections.value;

    await joined.load(const CollectionId.set('other'));

    expect(joined.collections.value, same(before));
  });

  test('stops publishing when disposed, and leaves the parts usable', () async {
    final before = joined.collections.value;
    joined.dispose();

    await catalogue.load(_people);
    await joined.load(_nature);

    expect(joined.collections.value, same(before));
    expect(
      catalogue.collections.value.first.contents,
      isA<CollectionContents$Loaded>(),
    );
  });
}
