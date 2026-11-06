/// A static sticker of the pack, from the bundle to a decoded image, through
/// the real image codec and no native library: fetcher, pipeline, scope.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_decoder/image_decoder.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  test('every sticker of the pack has a 512 px PNG with soft edges', () async {
    for (final sticker in StaticStickerPack.stickers) {
      final bytes = File(sticker.assetPath).readAsBytesSync();

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final pixels = (await image.toByteData())!.buffer.asUint8List();

      expect(codec.frameCount, 1, reason: sticker.name);
      expect(image.width, 512, reason: sticker.name);
      expect(image.height, 512, reason: sticker.name);
      final alphas = [for (var i = 3; i < pixels.length; i += 4) pixels[i]];
      expect(alphas.any((a) => a == 0), isTrue, reason: '${sticker.name} bg');
      expect(
        alphas.any((a) => a == 255),
        isTrue,
        reason: '${sticker.name} fill',
      );
      expect(
        alphas.any((a) => a > 0 && a < 255),
        isTrue,
        reason: '${sticker.name} soft edge',
      );
      image.dispose();
      codec.dispose();
    }
  });

  group('through the pipeline', () {
    late ManualPlaybackTickSource ticks;
    late AssetPipeline pipeline;
    late AssetCacheScope scope;

    setUp(() {
      ticks = ManualPlaybackTickSource();
      // The still form only: the animated one has no part in a sticker.
      pipeline = AssetPipeline(
        fetcher: BundledPacks.fetcher(_DiskBundle()),
        decoders: DecoderRegistry()
          ..register(MediaForm.still, const ImageCodecDecoder()),
      );
      BundledPacks.descriptors.forEach(pipeline.know);
      scope = AssetCacheScope(
        producer: pipeline,
        clock: PlaybackClock(ticks: ticks),
      );
    });
    tearDown(() {
      scope.dispose();
      pipeline.dispose();
    });

    test(
      'every sticker reaches full, still, and the clock never runs for it',
      () async {
        for (final sticker in StaticStickerPack.stickers) {
          final binding = scope.attach(
            sticker.key,
            const AssetSpec(pixelWidth: 128, pixelHeight: 128),
            const AssetProfile(animate: true),
          );
          final full = Completer<void>();
          void check() {
            if (binding.readiness.stage == AssetStage.full &&
                !full.isCompleted) {
              full.complete();
            }
          }

          binding.addListener(check);
          check();
          await full.future.timeout(const Duration(seconds: 10));

          expect(binding.paintable.isAnimated, isFalse, reason: sticker.name);
          expect(binding.isPlaying, isFalse, reason: sticker.name);
          expect(binding.lastError, isNull, reason: sticker.name);
          binding.detach();
        }
        expect(ticks.starts, 0);
        expect(ticks.isRunning, isFalse);
      },
    );
  });
}
