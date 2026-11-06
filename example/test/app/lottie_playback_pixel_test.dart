/// The pixel-only Lottie start (the web's): probed by starting an engine that
/// returns pixels, registered only when that works. The worker is the
/// protocol's in-memory fake, so this runs on the VM; the browser path is not
/// covered here.
library;

import 'dart:async';
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback_pixel.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  late PlaybackClock clock;
  late ChangeNotifier pressure;
  late ManualPlaybackTickSource ticks;

  setUp(() {
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    pressure = ChangeNotifier();
  });
  tearDown(() {
    clock.dispose();
    pressure.dispose();
  });

  Future<LottieEngine> spawnOver(FakeLottieWorker worker) =>
      WebWorkerLottieEngine.spawn(
        worker.port,
        wasmUrl: Uri.parse('https://host.test/chat_lottie.wasm'),
        wasmNoSimdUrl: Uri.parse('https://host.test/chat_lottie.nosimd.wasm'),
      );

  group('a sticker through the pipeline over the worker protocol', () {
    test('reaches full with a pixel-only engine, and close frees '
        'everything', () async {
      final sticker = LottieStickerPack.stickers.first;
      final bytes = await File(sticker.assetPath).readAsBytes();
      final worker = FakeLottieWorker()
        ..core.accept(
          bytes,
          const LottieInfo(
            width: 512,
            height: 512,
            frameCount: 120,
            frameRate: 60,
            features: LottieFeatures.none,
          ),
        );

      final playback = await startPixelLottiePlayback(
        clock: clock,
        memoryPressure: pressure,
        engineFactory: () => spawnOver(worker),
      );
      expect(playback, isNotNull);

      final pipeline = AssetPipeline(
        fetcher: BundledPacks.fetcher(_DiskBundle()),
        decoders: DecoderRegistry()
          ..register(MediaForm.vectorAnimation, playback!.decoder),
      );
      BundledPacks.descriptors.forEach(pipeline.know);
      final scope = AssetCacheScope(producer: pipeline, clock: clock);
      final attached = scope.attach(
        sticker.key,
        const AssetSpec(pixelWidth: 128, pixelHeight: 128),
        const AssetProfile(animate: true),
      );
      final full = Completer<void>();
      void check() {
        if (attached.readiness.stage == AssetStage.full && !full.isCompleted) {
          full.complete();
        }
      }

      attached.addListener(check);
      check();
      // The worker answers on microtasks and the pipeline reads the file on
      // the real clock, so the wait is real time, bounded.
      await full.future.timeout(const Duration(seconds: 10));

      expect(attached.paintable.isAnimated, isTrue);
      expect(attached.lastError, isNull);

      attached.detach();
      scope.dispose();
      pipeline.dispose();
      await playback.close();

      expect(worker.terminated, isTrue, reason: 'the engine was closed');
      await playback.close();
    });
  });

  group('an engine that cannot start', () {
    late List<String> logged;

    setUp(() {
      logged = [];
      final subscription = l.listen(
        (message) => logged.add('${message.message}'),
      );
      addTearDown(subscription.cancel);
    });

    test('a worker reporting unavailable gives no playback, and says so '
        'once', () async {
      final worker = FakeLottieWorker(unavailableReason: 'no wasm here');

      final playback = await startPixelLottiePlayback(
        clock: clock,
        memoryPressure: pressure,
        engineFactory: () => spawnOver(worker),
      );
      await Future<void>.delayed(Duration.zero);

      expect(playback, isNull);
      expect(logged.where((line) => line.contains('Lottie')), hasLength(1));
      expect(logged.single, contains('LottieUnavailable'));
      expect(logged.single, contains('no wasm here'));
    });

    testWidgets('a worker that never answers gives no playback once the '
        'spawn times out, and says so once', (tester) async {
      final worker = FakeLottieWorker(answersInit: false);
      var done = false;
      LottiePlayback? result;
      unawaited(
        startPixelLottiePlayback(
          clock: clock,
          memoryPressure: pressure,
          engineFactory: () => spawnOver(worker),
        ).then((playback) {
          done = true;
          result = playback;
        }),
      );

      // Fake time: the ready timeout is the engine's ten seconds.
      await tester.pump(const Duration(seconds: 9));
      expect(done, isFalse, reason: 'still waiting for ready');
      await tester.pump(const Duration(seconds: 2));

      expect(done, isTrue);
      expect(result, isNull);
      expect(logged.where((line) => line.contains('Lottie')), hasLength(1));
      expect(worker.terminated, isTrue);
    });
  });
}
