/// The content library's lists as the collections the stickers and GIF pages
/// list ahead of their packs and feeds.
///
/// **Seam:** [LibraryContentSource] over the lists of a library (here plain
/// notifiers standing in for a `DeferredLibraryView`), read through the
/// collections it publishes.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/library_content_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;

List<ContentKey> _keys(CollectionSource source, CollectionId id) {
  final collection = source.collections.value.singleWhere((c) => c.id == id);
  return switch (collection.contents) {
    CollectionContents$Loaded(:final items) => [
      for (final item in items) item.key,
    ],
    _ => throw StateError('not loaded: ${collection.contents}'),
  };
}

// 24 keys of stickers no pack describes but the test's describe does.
ContentKey _many(int i) => ContentKey.document('many:$i');

ContentDescriptor? _describe(ContentKey key) => switch (key) {
  ContentKey$Document(:final id) when id.startsWith('many:') =>
    ContentDescriptor(key: key, semanticKind: SemanticKind.sticker),
  _ =>
    LottieStickerPack.of(key)?.descriptor ??
        StaticStickerPack.of(key)?.descriptor ??
        VideoStickerPack.of(key)?.descriptor,
};

void main() {
  final star = LottieStickerPack.stickers.first.key;
  final sun = StaticStickerPack.stickers.first.key;
  final moon = StaticStickerPack.stickers[1].key;
  final clip = VideoStickerPack.clips.first.key;
  final gif = VideoStickerPack.gifs.first.key;

  late listen.ValueNotifier<List<ContentKey>> recents;
  late listen.ValueNotifier<List<ContentKey>> favourites;
  late listen.ValueNotifier<List<ContentKey>> saved;

  setUp(() {
    recents = listen.ValueNotifier(const []);
    favourites = listen.ValueNotifier(const []);
    saved = listen.ValueNotifier(const []);
    addTearDown(() {
      recents.dispose();
      favourites.dispose();
      saved.dispose();
    });
  });

  group('of the stickers page', () {
    late LibraryContentSource stickers;

    setUp(() {
      stickers = LibraryContentSource.stickers(
        recentStickers: recents,
        favouriteStickers: favourites,
        describe: _describe,
      );
      addTearDown(stickers.dispose);
    });

    test('is the favourites, then the recents, both loaded from the start', () {
      expect(
        [for (final c in stickers.collections.value) c.id],
        [CollectionId.faved, CollectionId.recent],
      );
      for (final collection in stickers.collections.value) {
        expect(collection.contents, isA<CollectionContents$Loaded>());
      }
    });

    test('lists each in the library\'s order, most recent first, as '
        'described content', () {
      recents.value = [sun, star];
      favourites.value = [moon];

      expect(_keys(stickers, CollectionId.recent), [sun, star]);
      expect(_keys(stickers, CollectionId.faved), [moon]);
      final first =
          (stickers.collections.value.last.contents
                  as CollectionContents$Loaded)
              .items
              .first;
      expect(first.descriptor?.spokenName, 'a sun');
    });

    test('does not list a favourite again among the recents', () {
      recents.value = [sun, star, moon];
      favourites.value = [star];

      expect(_keys(stickers, CollectionId.recent), [sun, moon]);
    });

    test('shows the first 20 recents of the 30 the library keeps', () {
      recents.value = [for (var i = 0; i < 30; i++) _many(i)];

      expect(_keys(stickers, CollectionId.recent), [
        for (var i = 0; i < 20; i++) _many(i),
      ]);
    });

    test('counts the 20 after taking the favourites out', () {
      recents.value = [for (var i = 0; i < 24; i++) _many(i)];
      favourites.value = [_many(0), _many(1)];

      expect(_keys(stickers, CollectionId.recent), [
        for (var i = 2; i < 22; i++) _many(i),
      ]);
    });

    test('leaves out content nothing describes', () {
      recents.value = [const ContentKey.document('gone'), sun];
      favourites.value = [const ContentKey.document('gone')];

      expect(_keys(stickers, CollectionId.recent), [sun]);
      expect(_keys(stickers, CollectionId.faved), isEmpty);
    });

    test('stops publishing once disposed', () {
      stickers.dispose();
      recents.value = [sun];

      expect(_keys(stickers, CollectionId.recent), isEmpty);
    });
  });

  group('of the GIF page', () {
    late LibraryContentSource gifs;

    setUp(() {
      gifs = LibraryContentSource.gifs(savedGifs: saved, describe: _describe);
      addTearDown(gifs.dispose);
    });

    test('is the saved GIFs as the page\'s recents, all of them, most '
        'recent first', () {
      saved.value = [gif, clip];

      expect(
        [for (final c in gifs.collections.value) c.id],
        [CollectionId.recent],
      );
      expect(_keys(gifs, CollectionId.recent), [gif, clip]);
    });
  });
}
