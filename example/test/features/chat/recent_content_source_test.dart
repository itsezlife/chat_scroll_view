/// The recent stickers and GIFs as a collection a page lists.
///
/// **Seam:** [RecentContentSource] over a recents store, read through the
/// collections it publishes.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/recent_content_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

List<ContentKey> _keys(CollectionSource source) {
  final collection = source.collections.value.single;
  return switch (collection.contents) {
    CollectionContents$Loaded(:final items) => [
      for (final item in items) item.key,
    ],
    _ => throw StateError('not loaded: ${collection.contents}'),
  };
}

void main() {
  late FakeRecentsStore recents;
  late RecentContentSource stickers;

  setUp(() {
    recents = FakeRecentsStore();
    stickers = RecentContentSource(
      recents: recents,
      kind: SemanticKind.sticker,
    );
    addTearDown(() {
      stickers.dispose();
      recents.dispose();
    });
  });

  test('is one loaded collection, the recents, from the start', () {
    final collection = stickers.collections.value.single;

    expect(collection.id, CollectionId.recent);
    expect(collection.contents, isA<CollectionContents$Loaded>());
    expect(_keys(stickers), isEmpty);
  });

  test('lists what the store holds for its kind, best first, as described '
      'content', () async {
    final star = LottieStickerPack.stickers.first;
    final orbit = VideoStickerPack.stickers.first;
    await recents.record(star.key, kind: SemanticKind.sticker);
    await recents.record(orbit.key, kind: SemanticKind.sticker);
    await recents.record(orbit.key, kind: SemanticKind.sticker);

    expect(_keys(stickers), [orbit.key, star.key]);
    final first =
        (stickers.collections.value.single.contents
                as CollectionContents$Loaded)
            .items
            .first;
    expect(first.descriptor?.spokenName, orbit.spokenName);
  });

  test('keeps the lists of the other kinds out', () async {
    final clip = VideoStickerPack.clips.first;
    await recents.record(clip.key, kind: SemanticKind.gif);

    expect(_keys(stickers), isEmpty);
  });

  test('leaves out content no pack describes', () async {
    await recents.record(
      const ContentKey.document('gone'),
      kind: SemanticKind.sticker,
    );

    expect(_keys(stickers), isEmpty);
  });

  test(
    'publishes again when the store changes, and not after dispose',
    () async {
      var published = 0;
      stickers.collections.addListener(() => published++);
      final star = LottieStickerPack.stickers.first;

      await recents.record(star.key, kind: SemanticKind.sticker);
      expect(published, 1);
      await recents.clear(kind: SemanticKind.sticker);
      expect(published, 2);
      expect(_keys(stickers), isEmpty);

      stickers.dispose();
      await recents.record(star.key, kind: SemanticKind.sticker);
      expect(published, 2);
    },
  );

  test('has nothing to load', () async {
    await stickers.load(CollectionId.recent);
    await stickers.loadMore(CollectionId.recent);

    expect(_keys(stickers), isEmpty);
  });
}
