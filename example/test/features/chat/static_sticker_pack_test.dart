import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaticStickerPack', () {
    test('describes each sticker as a still sticker', () {
      final descriptors = StaticStickerPack.descriptors.toList();

      expect(descriptors.length, inInclusiveRange(3, 4));
      for (final descriptor in descriptors) {
        expect(descriptor.key, isA<ContentKey$Document>());
        expect(descriptor.key.encoded, startsWith('document:demo-still:'));
        expect(descriptor.mediaForm, MediaForm.still);
        expect(descriptor.semanticKind, SemanticKind.sticker);
        expect(descriptor.animated, isFalse);
        expect(descriptor.size, const ContentSize(512, 512));
        expect(descriptor.spokenName, isNotEmpty);
      }
      expect(
        descriptors.map((descriptor) => descriptor.key).toSet(),
        hasLength(descriptors.length),
      );
    });

    test('finds a sticker by its key and no other content', () {
      for (final sticker in StaticStickerPack.stickers) {
        expect(StaticStickerPack.of(sticker.key), same(sticker));
      }
      expect(
        StaticStickerPack.of(const ContentKey.document('demo-lottie:star')),
        isNull,
      );
    });
  });
}
