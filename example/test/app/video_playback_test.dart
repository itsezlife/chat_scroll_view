/// The video decoder's start-up: probed by spawning the engine, registered
/// only when that works, and its parts stopped in order on close.
library;

import 'dart:async';
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/environment_specific/video_playback_vm.dart'
    as vm;
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

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

  group('start', () {
    late List<String> logged;

    setUp(() {
      logged = [];
      final subscription = l.listen(
        (message) => logged.add('${message.message}'),
      );
      addTearDown(subscription.cancel);
    });

    test(
      'an unavailable library gives no playback, and says so once',
      () async {
        final playback = await vm.$startVideoPlayback(
          clock: clock,
          memoryPressure: pressure,
          spawn: () async =>
              throw VideoUnavailable(VideoAvailability.missingLibrary),
        );
        await Future<void>.delayed(Duration.zero);

        expect(playback, isNull);
        expect(logged.where((line) => line.contains('Video')), hasLength(1));
        expect(logged.single, contains('missingLibrary'));
      },
    );

    test('any failure to start gives no playback, and says so once, with its '
        'type', () async {
      final playback = await vm.$startVideoPlayback(
        clock: clock,
        memoryPressure: pressure,
        spawn: () async => throw const FormatException('not a state error'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(playback, isNull);
      expect(logged.where((line) => line.contains('Video')), hasLength(1));
      expect(logged.single, contains('FormatException'));
    });
  });

  test('an engine that starts gives a decoder that takes a demo clip to full '
      'through the pipeline, and close disposes the engine', () async {
    final sticker = VideoStickerPack.stickers.first;
    final bytes = await File(sticker.assetPath).readAsBytes();
    final engine = FakeVideoEngine()
      ..accept(
        bytes,
        const VideoInfo(
          width: 512,
          height: 512,
          duration: Duration(seconds: 2),
          frameRate: 20,
          hasAlpha: true,
        ),
        frameCount: 40,
      );

    final playback = await vm.$startVideoPlayback(
      clock: clock,
      memoryPressure: pressure,
      spawn: () async => engine,
    );
    expect(playback, isNotNull);
    expect(playback!.decoder, isA<VideoDecoder>());

    final pipeline = AssetPipeline(
      fetcher: BundledPacks.fetcher(_DiskBundle()),
      decoders: DecoderRegistry()..register(MediaForm.video, playback.decoder),
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
    // The pipeline reads the file on the real clock, so the wait is real time,
    // bounded.
    await full.future.timeout(const Duration(seconds: 10));

    expect(attached.paintable.isAnimated, isTrue);
    expect(attached.lastError, isNull);
    expect(engine.openClips, 1);

    attached.detach();
    scope.dispose();
    pipeline.dispose();
    await playback.close();

    expect(engine.openClips, 0, reason: 'the engine was disposed');
    await expectLater(
      engine.open(bytes, width: 64, height: 64),
      throwsA(isA<VideoEngineClosed>()),
    );
    await playback.close();
  });

  group('VideoPlayback', () {
    test('closes its steps in the order given, once', () async {
      final order = <String>[];
      final playback = VideoPlayback(
        decoder: FakeDecoder(),
        shutdown: [
          () => order.add('scheduler'),
          () async => order.add('engine'),
        ],
      );

      await playback.close();
      await playback.close();

      expect(order, ['scheduler', 'engine']);
    });

    test('a failing step does not skip the ones after it, and is '
        'rethrown', () async {
      final order = <String>[];
      final playback = VideoPlayback(
        decoder: FakeDecoder(),
        shutdown: [
          () async => throw StateError('scheduler would not stop'),
          () => order.add('engine'),
        ],
      );

      await expectLater(playback.close(), throwsStateError);

      expect(order, ['engine'], reason: 'the engine still goes');
    });
  });
}
