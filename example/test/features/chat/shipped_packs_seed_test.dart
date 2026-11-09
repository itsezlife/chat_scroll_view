/// The packs the app ships, installed once each.
///
/// **Seam:** [ShippedPacksSeed] loaded from and installing through a fake key-value store and a fake
/// content library, read through the library's installed packs.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/shipped_packs_seed.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeKeyValueStore store;
  late FakeContentLibrary library;

  setUp(() {
    store = FakeKeyValueStore();
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
    addTearDown(library.dispose);
  });

  const a = (id: PackId('a'), kind: PackKind.stickers);
  const b = (id: PackId('b'), kind: PackKind.stickers);
  const e = (id: PackId('e'), kind: PackKind.emoji);

  List<PackId> installed(PackKind kind) => library.installedPacks(kind).value;

  test(
    'the first run installs every shipped pack, in the shipped order',
    () async {
      await (await ShippedPacksSeed.load(store)).install(library, [a, b, e]);

      expect(installed(PackKind.stickers), [a.id, b.id]);
      expect(installed(PackKind.emoji), [e.id]);
    },
  );

  test('a pack the user removed stays removed', () async {
    await (await ShippedPacksSeed.load(store)).install(library, [a, b]);
    library.apply(LibraryEdit.removePack(a.id, a.kind));

    await (await ShippedPacksSeed.load(store)).install(library, [a, b]);

    expect(installed(PackKind.stickers), [b.id]);
  });

  test('a pack shipped later is installed on the next run', () async {
    await (await ShippedPacksSeed.load(store)).install(library, [a]);

    await (await ShippedPacksSeed.load(store)).install(library, [a, b]);

    expect(installed(PackKind.stickers), [b.id, a.id]);
  });

  test('a store that cannot be read seeds nothing and fails nothing', () async {
    store.failure = Exception('locked');

    await (await ShippedPacksSeed.load(store)).install(library, [a]);

    expect(installed(PackKind.stickers), isEmpty);
  });
}
