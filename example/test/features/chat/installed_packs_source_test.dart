/// The installed packs of one kind as the collections a panel page lists.
///
/// **Seam:** [InstalledPacksSource] over a fake content library and a fake
/// pack source, read through the collections it publishes.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/installed_packs_source.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Pack _pack(String id, {PackKind kind = PackKind.stickers}) => Pack(
  id: PackId(id),
  kind: kind,
  title: 'Pack $id',
  items: [
    ContentDescriptor(
      key: ContentKey.document('$id-0'),
      semanticKind: kind.itemKind,
    ),
  ],
);

void main() {
  late FakePackSource packs;
  late FakeContentLibrary library;
  late InstalledPacksSource source;

  setUp(() {
    packs = FakePackSource([
      _pack('a'),
      _pack('b'),
      _pack('e', kind: PackKind.emoji),
    ]);
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
    addTearDown(() {
      source.dispose();
      packs.dispose();
      library.dispose();
    });
  });

  void install(String id, [PackKind kind = PackKind.stickers]) =>
      library.apply(LibraryEdit.installPack(PackId(id), kind));

  List<CollectionId> ids() => [
    for (final collection in source.collections.value) collection.id,
  ];

  test('lists the installed packs of its kind in the library order', () async {
    install('a');
    install('b');
    install('e', PackKind.emoji);
    source = InstalledPacksSource(
      kind: PackKind.stickers,
      library: library,
      packs: packs,
    );
    await pumpEventQueue();

    // Installing puts a pack first.
    expect(ids(), [const CollectionId.set('b'), const CollectionId.set('a')]);
    final first = source.collections.value.first;
    expect(first.metadata.title, 'Pack b');
    expect(first.contents, isA<CollectionContents$Loaded>());
  });

  test('a pack still being looked up is listed as loading', () async {
    packs.gate.pause();
    install('a');
    source = InstalledPacksSource(
      kind: PackKind.stickers,
      library: library,
      packs: packs,
    );

    expect(
      source.collections.value.single.contents,
      isA<CollectionContents$Loading>(),
    );

    packs.gate.resume();
    await pumpEventQueue();

    expect(
      source.collections.value.single.contents,
      isA<CollectionContents$Loaded>(),
    );
  });

  test('follows installs and removals', () async {
    source = InstalledPacksSource(
      kind: PackKind.stickers,
      library: library,
      packs: packs,
    );
    expect(ids(), isEmpty);

    install('a');
    await pumpEventQueue();
    expect(ids(), [const CollectionId.set('a')]);

    library.apply(const LibraryEdit.removePack(PackId('a'), PackKind.stickers));
    expect(ids(), isEmpty);
  });

  test('a pack the source cannot find is left out', () async {
    install('gone');
    source = InstalledPacksSource(
      kind: PackKind.stickers,
      library: library,
      packs: packs,
    );
    await pumpEventQueue();

    expect(ids(), isEmpty);
  });
}
