import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

Future<ui.Image> _upload(Uint8List pixels, int side) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return Future.value(image);
}

/// 30 fps, 3 frames: pts 0, 33, 67 ms (the fake's), loop length 100 ms.
const _info = VideoInfo(
  width: 16,
  height: 16,
  duration: Duration(milliseconds: 100),
  frameRate: 30,
  hasAlpha: true,
);

/// A writer that also keeps the first pixel of each frame it was handed, as
/// the source gave it while the batch ran.
final class _ReadingWriter implements TextureFrameWriter {
  final FakeTextureFrameWriter inner = FakeTextureFrameWriter();
  final List<List<int>> firstPixels = [];

  @override
  Future<List<TextureFrameOutcome>> write(List<TextureFrameJob> jobs) {
    for (final job in jobs) {
      final pixels = (job.source as VideoFrameSource).pixelsOf(job.frame)!;
      firstPixels.add(pixels.sublist(0, 4));
    }
    return inner.write(jobs);
  }
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  late FakeVideoEngine engine;
  late FakeFrameTextureHost host;
  late FrameTexturePool pool;
  late _ReadingWriter writer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late VideoFrameScheduler scheduler;
  var time = Duration.zero;

  Future<VideoClip> openClip() async {
    final result = await engine.open(bytes, width: 16, height: 8);
    return (result as VideoClipOpened).clip;
  }

  Future<void> tick() async {
    time += const Duration(milliseconds: 16);
    ticks.tick(time);
    await pumpEventQueue();
  }

  Future<void> settle([int count = 6]) async {
    for (var i = 0; i < count; i++) {
      await tick();
    }
  }

  // Wants the clip's next three frames from [from]: a texture is shown after
  // three posts of its lease.
  Future<void> playThree(
    VideoFrameLease lease, {
    Duration from = Duration.zero,
  }) async {
    for (final ms in const [0, 34, 67]) {
      scheduler.want(lease, from + Duration(milliseconds: ms));
      await settle();
    }
  }

  setUp(() {
    time = Duration.zero;
    engine = FakeVideoEngine()..accept(bytes, _info, frameCount: 3);
    host = FakeFrameTextureHost();
    pool = FrameTexturePool(host: host, sizeClasses: const [64]);
    writer = _ReadingWriter();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = VideoFrameScheduler(
      engine: engine,
      atlas: VideoFrameAtlas.create(upload: _upload, sizeClasses: const [64]),
      clock: clock,
      textures: pool,
      textureWriter: writer,
      startTimer: timers.start,
    );
  });
  tearDown(() async {
    scheduler.dispose();
    pool.dispose();
    clock.dispose();
    await engine.dispose();
  });

  group('VideoFrameScheduler with textures', () {
    test(
      'a clip on a free texture has its decoded frames written there',
      () async {
        await pool.warm(64, 1);
        final lease = scheduler.acquire('a', await openClip())!;

        await playThree(lease);

        final job = writer.inner.batches.first.single;
        expect(
          job.texture,
          AssetTexture(
            id: host.liveIds.single,
            width: 64,
            height: 64,
            frameWidth: 16,
            frameHeight: 8,
          ),
        );
        expect((job.width, job.height), (16, 8));
        // Frame 0 of the fake: blue 0, green 0, red 0, alpha 200.
        expect(writer.firstPixels.first, [0, 0, 0, 200]);
        expect(lease.texture?.id, host.liveIds.single);
        expect(lease.sprite, isNull);

        expect(writer.firstPixels[1], [16, 8, 0, 200]);
      },
    );

    test('the texture names the frame it holds, centred in it', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip())!;

      await playThree(lease);

      final texture = lease.texture!;
      expect((texture.width, texture.height), (64, 64));
      expect((texture.frameWidth, texture.frameHeight), (16, 8));
    });

    test('the texture shows only after three posts', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip())!;
      writer.inner.pause();

      scheduler.want(lease, Duration.zero);
      await settle();
      expect(lease.texture, isNull);

      writer.inner.resume();
      await pumpEventQueue();
      // The texture may still queue frames of the clip that held it, which
      // the engine would show first.
      expect(lease.texture, isNull, reason: 'one post');
      scheduler.want(lease, const Duration(milliseconds: 34));
      await settle();
      expect(lease.texture, isNull, reason: 'two posts');
      scheduler.want(lease, const Duration(milliseconds: 67));
      await settle();
      expect(lease.texture, isNotNull);
    });

    test(
      'a clip with no free texture plays on a slot and warms its class',
      () async {
        final lease = scheduler.acquire('a', await openClip())!;
        expect(host.created, isEmpty);

        await Future<void>.delayed(Duration.zero);
        await pumpEventQueue();
        expect(host.created, hasLength(1));

        await playThree(lease, from: const Duration(milliseconds: 34));
        expect(lease.texture, isNotNull, reason: 'moved to the warmed one');
        expect(lease.sprite, isNull);
      },
    );

    test('locks that keep failing send the clip back to a slot', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip())!;
      final id = host.liveIds.single;
      writer.inner.outcomeOf[id] = TextureFrameOutcome.notLocked;

      for (var ms = 0; ms <= 200; ms += 16) {
        scheduler.want(lease, Duration(milliseconds: ms));
        await tick();
      }

      expect(
        writer.inner.batches,
        hasLength(VideoFrameScheduler.lockFailureLimit),
      );
      expect(host.destroyed, [id]);
      expect(lease.texture, isNull);
      expect(lease.sprite, isNotNull);
    });

    test('a canvas paint keeps the clip on a slot', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip(), onCanvas: true)!;

      scheduler.want(lease, Duration.zero, onCanvas: true);
      await settle();

      expect(writer.inner.batches, isEmpty);
      expect(lease.sprite, isNotNull);
      expect(pool.idleTextures, 1);
    });

    test('textures switched off send the clip to a slot', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip())!;
      await playThree(lease);
      expect(lease.texture, isNotNull);

      scheduler.texturesEnabled = false;
      scheduler.want(lease, const Duration(milliseconds: 134));
      await settle();

      expect(lease.texture, isNull);
      expect(lease.sprite, isNotNull);
      expect(pool.idleTextures, 1);
    });

    test('an unpainted clip gives its texture back on the sweep', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip())!;
      scheduler.want(lease, Duration.zero);
      await settle();

      timers
        ..elapse(const Duration(seconds: 1))
        ..elapse(const Duration(seconds: 1));
      await pumpEventQueue();

      expect(lease.isReleased, isTrue);
      expect(pool.leasedTextures, 0);
      expect(pool.idleTextures, 1);
    });

    test('a kept clip keeps its texture through the sweeps and posts '
        'nothing, and is swept once it is let go', () async {
      await pool.warm(64, 1);
      final lease = scheduler.acquire('a', await openClip())!;
      await playThree(lease);
      final shown = lease.texture;
      expect(shown, isNotNull);
      final writes = writer.inner.batches.length;

      lease.kept = true;
      for (var i = 0; i < 3; i++) {
        timers.elapse(const Duration(seconds: 1));
        await settle();
      }

      expect(lease.isReleased, isFalse);
      expect(lease.texture, shown);
      expect(writer.inner.batches, hasLength(writes));

      lease.kept = false;
      timers
        ..elapse(const Duration(seconds: 1))
        ..elapse(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(lease.isReleased, isTrue);
    });
  });
}
