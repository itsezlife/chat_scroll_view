import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/frame_counter_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(key);
    if (!file.existsSync()) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(await file.readAsBytes());
  }
}

FetchRequest _request(ContentDescriptor descriptor, {FetchPart? part}) =>
    FetchRequest(
      descriptor: descriptor,
      part: part ?? FetchPart.content,
      priority: AssetPriority.visible,
      cancellation: CancellationToken(),
    );

void main() {
  final emoji = AnimatedEmojiPack.emoji.first;
  final sticker = LottieStickerPack.stickers.first;
  final still = StaticStickerPack.stickers.first;
  final video = VideoStickerPack.stickers.first;

  test('lists the descriptors of every pack', () {
    expect(BundledPacks.descriptors, [
      ...AnimatedEmojiPack.descriptors,
      ...LottieStickerPack.descriptors,
      ...StaticStickerPack.descriptors,
      ...VideoStickerPack.descriptors,
      ...FrameCounterPack.descriptors,
    ]);
  });

  test('finds an item of any pack by its key and no other content', () {
    expect(BundledPacks.of(emoji.key), same(emoji));
    expect(BundledPacks.of(sticker.key), same(sticker));
    expect(BundledPacks.of(still.key), same(still));
    expect(BundledPacks.of(video.key), same(video));
    expect(BundledPacks.of(const ContentKey.document('other')), isNull);
    expect(BundledPacks.of(const ContentKey.unicode('\u{1F600}')), isNull);
  });

  group('packs', () {
    test('every sticker and animated emoji names the pack it is listed in; '
        'a clip or a GIF names none', () {
      for (final item in AnimatedEmojiPack.emoji) {
        expect(item.descriptor.pack, const PackId('noto_animated_emoji'));
      }
      for (final item in LottieStickerPack.stickers) {
        expect(item.descriptor.pack, const PackId('demo_lottie'));
      }
      for (final item in StaticStickerPack.stickers) {
        expect(item.descriptor.pack, const PackId('demo_still'));
      }
      for (final item in VideoStickerPack.stickers) {
        expect(item.descriptor.pack, const PackId('demo_video'));
      }
      for (final item in [
        ...VideoStickerPack.clips,
        ...VideoStickerPack.gifs,
      ]) {
        expect(item.descriptor.pack, isNull, reason: item.name);
      }
    });

    test('serves each pack by its id: its kind, title and items in order, '
        'listed as the collection the page shows it as', () {
      final lottie = BundledPacks.packOf(const PackId('demo_lottie'))!;
      expect(lottie.kind, PackKind.stickers);
      expect(lottie.title, LottieStickerPack.title);
      expect(lottie.items, LottieStickerPack.descriptors.toList());
      expect(lottie.collectionId, LottieStickerPack.id);

      final emojiPack = BundledPacks.packOf(
        const PackId('noto_animated_emoji'),
      )!;
      expect(emojiPack.kind, PackKind.emoji);
      expect(emojiPack.items, AnimatedEmojiPack.descriptors.toList());

      expect(
        BundledPacks.packOf(const PackId('demo_still'))!.items,
        StaticStickerPack.descriptors.toList(),
      );
      // The WebM stickers alone: a clip is no sticker of a pack.
      expect(BundledPacks.packOf(const PackId('demo_video'))!.items, [
        for (final item in VideoStickerPack.stickers) item.descriptor,
      ]);
    });

    test('serves nothing for an id that is no bundled pack', () {
      expect(BundledPacks.packOf(const PackId('demo_gifs')), isNull);
      expect(BundledPacks.packOf(const PackId('other')), isNull);
    });
  });

  test('a pack source lists its items loaded, every one described', () {
    final source = BundledPackSource(
      id: LottieStickerPack.id,
      title: LottieStickerPack.title,
      items: LottieStickerPack.stickers,
    );
    addTearDown(source.dispose);

    final collection = source.collections.value.single;
    expect(collection.id, LottieStickerPack.id);
    expect(collection.metadata.title, LottieStickerPack.title);
    expect(collection.metadata.flags, CollectionFlags.installed);
    final contents = collection.contents as CollectionContents$Loaded;
    expect([
      for (final item in contents.items) item.descriptor,
    ], LottieStickerPack.descriptors.toList());
    expect(contents.nextPageToken, isNull);
  });

  group('the fetcher', () {
    final fetcher = BundledPacks.fetcher(_DiskBundle());

    test('reads an emoji and a sticker from the bundle', () async {
      final stillContent = await fetcher.fetch(_request(still.descriptor));
      final emojiContent = await fetcher.fetch(_request(emoji.descriptor));
      final stickerContent = await fetcher.fetch(_request(sticker.descriptor));
      final videoContent = await fetcher.fetch(_request(video.descriptor));

      expect(
        (emojiContent as FetchedBytes).bytes,
        File('assets/animated_emoji/${emoji.code}.webp').readAsBytesSync(),
      );
      expect(
        (stickerContent as FetchedBytes).bytes,
        File(sticker.assetPath).readAsBytesSync(),
      );
      expect(
        (stillContent as FetchedBytes).bytes,
        File(still.assetPath).readAsBytesSync(),
      );
      expect(
        (videoContent as FetchedBytes).bytes,
        File(video.assetPath).readAsBytesSync(),
      );
    });

    test('fails other content, and a thumbnail nobody has, for good', () async {
      const other = ContentDescriptor(key: ContentKey.document('other'));

      for (final request in [
        _request(other),
        _request(sticker.descriptor, part: FetchPart.thumbnail),
      ]) {
        await expectLater(
          fetcher.fetch(request),
          throwsA(
            isA<FetchFailure>().having(
              (failure) => failure.kind,
              'kind',
              AssetFailureKind.permanent,
            ),
          ),
        );
      }
    });
  });

  test(
    'the resolver describes the keys of every pack and nothing else',
    () async {
      final found = await BundledPacks.resolver().resolve([
        emoji.key,
        sticker.key,
        still.key,
        video.key,
        const ContentKey.document('other'),
      ]);

      expect(found, {
        emoji.key: emoji.descriptor,
        sticker.key: sticker.descriptor,
        still.key: still.descriptor,
        video.key: video.descriptor,
      });
    },
  );
}
