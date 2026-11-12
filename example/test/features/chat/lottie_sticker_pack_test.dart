import 'dart:io';

import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';

void main() {
  group('LottieStickerPack', () {
    test('describes each sticker as an animated vector sticker', () {
      final descriptors = LottieStickerPack.descriptors.toList();

      expect(descriptors.length, inInclusiveRange(3, 4));
      for (final descriptor in descriptors) {
        expect(descriptor.key, isA<ContentKey$Document>());
        expect(descriptor.key.encoded, startsWith('document:demo-lottie:'));
        expect(descriptor.mediaForm, MediaForm.vectorAnimation);
        expect(descriptor.semanticKind, SemanticKind.sticker);
        expect(descriptor.animated, isTrue);
        expect(descriptor.size, const ContentSize(512, 512));
        expect(descriptor.spokenName, isNotEmpty);
      }
      expect(
        descriptors.map((descriptor) => descriptor.key).toSet(),
        hasLength(descriptors.length),
      );
    });

    test('finds a sticker by its key and no other content', () {
      for (final sticker in LottieStickerPack.stickers) {
        expect(LottieStickerPack.of(sticker.key), same(sticker));
      }
      expect(
        LottieStickerPack.of(const ContentKey.document('noto-animated:1f600')),
        isNull,
      );
    });

    // The wrapper refuses files it cannot draw, so a file that loads is one
    // the example can show. Skipped where the library is not built.
    final binding = NativeLottieBinding.probe();
    tearDownAll(binding.close);
    for (final sticker in LottieStickerPack.stickers) {
      test(
        '${sticker.name} loads through the native binding',
        () {
          final bytes = File(sticker.assetPath).readAsBytesSync();

          final result = binding.load(bytes);

          expect(result, isA<LottieLoaded>());
          final info = (result as LottieLoaded).info;
          expect(info.width, 512);
          expect(info.height, 512);
          expect(info.frameRate, 60);
          expect(info.frameCount, inInclusiveRange(100, 140));
          expect(info.features, LottieFeatures.none);
          binding.dispose(result.handle);
        },
        skip: binding.isAvailable
            ? false
            : 'the native library is not available: ${binding.availability}',
      );
    }
  });
}
