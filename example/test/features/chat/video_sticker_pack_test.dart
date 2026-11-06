import 'dart:io';

import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoStickerPack', () {
    test('holds three WebM stickers, two MP4 clips and two GIFs', () {
      expect(VideoStickerPack.stickers, hasLength(3));
      expect(VideoStickerPack.clips, hasLength(2));
      expect(VideoStickerPack.gifs, hasLength(2));
      expect(VideoStickerPack.items, [
        ...VideoStickerPack.stickers,
        ...VideoStickerPack.clips,
        ...VideoStickerPack.gifs,
      ]);
    });

    test('describes every item as animated video content', () {
      final descriptors = VideoStickerPack.descriptors.toList();

      expect(descriptors, hasLength(7));
      for (final descriptor in descriptors) {
        expect(descriptor.key, isA<ContentKey$Document>());
        expect(descriptor.key.encoded, startsWith('document:demo-video:'));
        expect(descriptor.mediaForm, MediaForm.video);
        expect(descriptor.animated, isTrue);
        expect(descriptor.spokenName, isNotEmpty);
      }
      expect(
        descriptors.map((descriptor) => descriptor.key).toSet(),
        hasLength(descriptors.length),
      );
    });

    test('says a WebM is a 512 sticker and a clip or a GIF is a gif', () {
      for (final sticker in VideoStickerPack.stickers) {
        expect(sticker.descriptor.semanticKind, SemanticKind.sticker);
        expect(sticker.descriptor.size, const ContentSize(512, 512));
        expect(sticker.assetPath, endsWith('.webm'));
      }
      for (final item in [
        ...VideoStickerPack.clips,
        ...VideoStickerPack.gifs,
      ]) {
        expect(item.descriptor.semanticKind, SemanticKind.gif);
      }
      expect(
        VideoStickerPack.clips.map((c) => c.assetPath),
        everyElement(endsWith('.mp4')),
      );
      expect(
        VideoStickerPack.gifs.map((g) => g.assetPath),
        everyElement(endsWith('.gif')),
      );
    });

    test('finds an item by its key and no other content', () {
      for (final item in VideoStickerPack.items) {
        expect(VideoStickerPack.of(item.key), same(item));
      }
      expect(
        VideoStickerPack.of(const ContentKey.document('demo-lottie:star')),
        isNull,
      );
    });

    test('has a small file on disk for every item', () {
      for (final item in VideoStickerPack.items) {
        final file = File(item.assetPath);

        expect(file.existsSync(), isTrue, reason: item.assetPath);
        expect(
          file.lengthSync(),
          inInclusiveRange(1, 200 * 1024),
          reason: item.assetPath,
        );
      }
    });

    test('lists as one installed collection holding every item', () {
      final source = VideoStickerPack.source();
      addTearDown(source.dispose);

      final collection = source.collections.value.single;

      expect(collection.id, VideoStickerPack.id);
      expect(collection.metadata.title, VideoStickerPack.title);
      expect(
        (collection.contents as CollectionContents$Loaded).items.map(
          (item) => item.key,
        ),
        VideoStickerPack.items.map((item) => item.key),
      );
    });
  });
}
