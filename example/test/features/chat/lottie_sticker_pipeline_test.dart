/// A sticker of the pack, from the bundle to pixels, through the real native
/// library: fetcher, pipeline, `LottieDecoder` over the render isolate, the
/// frame atlas and the scheduler on a hand-ticked clock.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

const _side = 128;
const _spec = AssetSpec(pixelWidth: _side, pixelHeight: _side);

Future<Uint8List> _pixels(AssetBinding binding) async {
  final recorder = ui.PictureRecorder();
  binding.paint(
    ui.Canvas(recorder),
    ui.Rect.fromLTWH(0, 0, _side.toDouble(), _side.toDouble()),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_side, _side);
  picture.dispose();
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  final binding = NativeLottieBinding.probe();
  final unavailable = binding.isAvailable
      ? null
      : 'the native library is not available: ${binding.availability}';
  binding.close();

  group('a Lottie sticker through the pipeline', () {
    late IsolateLottieEngine engine;
    late NativeFramePageMemory memory;
    late ManualPlaybackTickSource ticks;
    late PlaybackClock clock;
    late ManualRetentionTimers timers;
    late LottieFrameScheduler scheduler;
    late AssetPipeline pipeline;
    late AssetCacheScope scope;
    var time = Duration.zero;

    setUp(() async {
      engine = await IsolateLottieEngine.spawn();
      memory = NativeFramePageMemory(pageSide: FrameAtlas.defaultPageSide);
      ticks = ManualPlaybackTickSource();
      clock = PlaybackClock(ticks: ticks);
      timers = ManualRetentionTimers();
      scheduler = LottieFrameScheduler(
        atlas: FrameAtlas<Object>(
          renderer: LottieFrameRenderer(engine: engine, memory: memory),
          memory: memory,
        ),
        clock: clock,
        startTimer: timers.start,
      );
      pipeline = AssetPipeline(
        fetcher: BundledPacks.fetcher(_DiskBundle()),
        decoders: DecoderRegistry()
          ..register(
            MediaForm.vectorAnimation,
            LottieDecoder(engine: engine, scheduler: scheduler),
          ),
      );
      BundledPacks.descriptors.forEach(pipeline.know);
      scope = AssetCacheScope(producer: pipeline, clock: clock);
      time = Duration.zero;
    });
    tearDown(() async {
      scope.dispose();
      pipeline.dispose();
      scheduler.dispose();
      await engine.close();
      memory.dispose();
      clock.dispose();
    });

    Future<AssetBinding> attachFull(LottieSticker sticker) async {
      final attached = scope.attach(
        sticker.key,
        _spec,
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
      await full.future.timeout(const Duration(seconds: 10));
      return attached;
    }

    /// One clock frame of 16 ms, then room for the isolate to answer.
    Future<void> frame() async {
      time += const Duration(milliseconds: 16);
      ticks.tick(time);
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }

    test('every sticker of the pack reaches full', () async {
      for (final sticker in LottieStickerPack.stickers) {
        final attached = await attachFull(sticker);

        expect(attached.paintable.isAnimated, isTrue, reason: sticker.name);
        expect(attached.lastError, isNull, reason: sticker.name);
        attached.detach();
      }
    });

    test(
      'paints a rendered frame after a few ticks, not only its still',
      () async {
        final attached = await attachFull(LottieStickerPack.stickers.first);
        addTearDown(attached.detach);
        final still = await _pixels(attached);
        expect(
          still.any((byte) => byte != 0),
          isTrue,
          reason: 'the still draws',
        );

        for (var i = 0; i < 40; i++) {
          await frame();
          await _pixels(attached);
        }

        final moving = await _pixels(attached);
        expect(moving, isNot(still), reason: 'a later frame is on the canvas');
        expect(scheduler.leaseCount, 1);
      },
    );

    test(
      'gives its slot back once it is not painted for the idle period',
      () async {
        final attached = await attachFull(LottieStickerPack.stickers.first);
        addTearDown(attached.detach);
        for (var i = 0; i < 5; i++) {
          await frame();
          await _pixels(attached);
        }
        expect(scheduler.leaseCount, 1);

        // The sweep timer is the scheduler's own seam, so the idle period is
        // stepped by hand: no wall-clock wait, no margin to tune. The first
        // sweep sees the last paint, the second finds nothing since.
        timers.elapse(scheduler.idleRelease);
        expect(scheduler.leaseCount, 1);
        timers.elapse(scheduler.idleRelease);

        expect(scheduler.leaseCount, 0);
      },
    );
  }, skip: unavailable);
}
