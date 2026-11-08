import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

Future<ui.Image> _upload(Uint8List pixels, int side) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return Future.value(image);
}

void main() {
  late FakeFrameRenderer renderer;
  late FakeFrameTextureHost host;
  late FrameTexturePool pool;
  late FakeTextureFrameWriter writer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late LottieFrameScheduler scheduler;
  var time = Duration.zero;

  Future<void> tick() async {
    time += const Duration(milliseconds: 16);
    ticks.tick(time);
    await pumpEventQueue();
  }

  // The two ticks a posted texture waits before it is shown.
  Future<void> untilShown() async {
    await tick();
    await tick();
  }

  setUp(() {
    time = Duration.zero;
    renderer = FakeFrameRenderer();
    host = FakeFrameTextureHost();
    pool = FrameTexturePool(host: host, sizeClasses: const [64]);
    writer = FakeTextureFrameWriter();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: renderer,
        memory: ListFramePageMemory(),
        budgetBytes: 2 * 128 * 128 * 4,
        sizeClasses: const [64],
        upload: _upload,
      ),
      clock: clock,
      textures: pool,
      textureWriter: writer,
      startTimer: timers.start,
    );
  });
  tearDown(() {
    scheduler.dispose();
    pool.dispose();
    clock.dispose();
  });

  LottieFrameLease lease(String key, {Object source = 'src'}) =>
      scheduler.acquire(key, source, 48, 32)!;

  group('LottieFrameScheduler with textures', () {
    test(
      'a lease takes a free texture and writes there, not on a page',
      () async {
        await pool.warm(64, 1);
        final a = lease('a');

        scheduler.want(a, 3);
        await tick();

        expect(renderer.batches, isEmpty);
        expect(writer.batches, hasLength(1));
        final job = writer.batches.single.single;
        expect(job.frame, 3);
        expect((job.width, job.height), (48, 32));
        expect(
          job.texture,
          AssetTexture(
            id: host.liveIds.single,
            width: 64,
            height: 64,
            frameWidth: 48,
            frameHeight: 32,
          ),
        );
        expect(job.source, 'src');
      },
    );

    test('exposes the texture only two ticks after its first post', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      expect(a.texture, isNull);

      writer.pause();
      scheduler.want(a, 1);
      await tick();
      expect(a.texture, isNull, reason: 'the write is still running');
      expect(a.sprite, isNull, reason: 'the still shows meanwhile');

      writer.resume();
      await pumpEventQueue();
      // A texture another asset held shows that asset's frame until the
      // engine takes the post.
      expect(a.texture, isNull, reason: 'posted, not taken yet');

      await tick();
      expect(a.texture, isNull, reason: 'one tick after the post');
      await tick();
      expect(a.texture?.id, host.liveIds.single);
      expect(a.sprite, isNull);
    });

    test(
      'takes a page slot exactly as before when no texture is free',
      () async {
        final a = lease('a');

        scheduler.want(a, 2);
        await tick();

        expect(writer.batches, isEmpty);
        expect(renderer.batches, [
          [2],
        ]);
        expect(a.sprite, isNotNull);
        expect(a.texture, isNull);
      },
    );

    test('a lease that found none warms its class, off the lease', () async {
      lease('a');
      lease('b');
      expect(host.created, isEmpty, reason: 'a lease never creates one');

      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();

      expect(host.created, hasLength(2));
      expect(pool.idleTextures, 2);
    });

    test('moves to a texture that comes free, keeping its slot until the '
        'texture is shown', () async {
      final a = lease('a');
      scheduler.want(a, 1);
      await tick();
      expect(a.sprite, isNotNull);
      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();
      expect(pool.idleTextures, 1, reason: 'warmed for it');

      writer.pause();
      scheduler.want(a, 2);
      await tick();
      expect(pool.leasedTextures, 1);
      expect(a.sprite, isNotNull, reason: 'the slot shows until the post');
      expect(renderer.batches, hasLength(1), reason: 'no slot frame meanwhile');

      writer.resume();
      await pumpEventQueue();
      expect(a.texture, isNull);
      expect(a.sprite, isNotNull, reason: 'the slot shows until it is shown');

      await untilShown();
      expect(a.texture, isNotNull);
      expect(a.sprite, isNull);
    });

    test('a texture is written at most once a clock frame', () async {
      await pool.warm(64, 1);
      final a = lease('a');

      scheduler
        ..want(a, 1)
        ..want(a, 2)
        ..want(a, 3);
      await tick();
      writer.pause();
      scheduler.want(a, 4);
      await tick();
      scheduler.want(a, 5);
      await tick();
      writer.resume();
      await pumpEventQueue();
      await tick();

      expect(
        [for (final batch in writer.batches) batch.single.frame],
        [3, 4, 5],
      );
    });

    test('a lock that fails skips the frame and asks it again', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      final id = host.liveIds.single;
      scheduler.want(a, 1);
      await tick();
      await untilShown();

      writer.outcomeOf[id] = TextureFrameOutcome.notLocked;
      scheduler.want(a, 2);
      await tick();
      expect(a.texture?.id, id, reason: 'it keeps its previous frame');

      writer.outcomeOf.remove(id);
      await tick();
      expect(
        [for (final batch in writer.batches) batch.single.frame],
        [1, 2, 2],
      );
    });

    test('locks that keep failing send the asset back to a page slot for '
        'good', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      final id = host.liveIds.single;
      writer.outcomeOf[id] = TextureFrameOutcome.notLocked;

      for (
        var frame = 1;
        frame <= LottieFrameScheduler.lockFailureLimit;
        frame++
      ) {
        scheduler.want(a, frame);
        await tick();
      }

      expect(a.texture, isNull);
      expect(host.destroyed, [id], reason: 'a broken texture is not reused');
      scheduler.want(a, 9);
      await tick();
      expect(renderer.batches.last, [9]);
      expect(a.sprite, isNotNull);

      a.release();
      await pool.warm(64, 1);
      final again = lease('a');
      scheduler.want(again, 10);
      await tick();
      expect(renderer.batches.last, [10], reason: 'never a texture again');
    });

    test('a job whose source failed fails the lease', () async {
      await pool.warm(64, 1);
      final bad = lease('bad', source: FakeTextureFrameWriter.rejected);

      scheduler.want(bad, 1);
      await tick();

      expect(bad.isFailed, isTrue);
      expect(bad.texture, isNull);
    });

    test(
      'an unpainted lease gives its texture back to idle on the sweep',
      () async {
        await pool.warm(64, 1);
        final a = lease('a');
        scheduler.want(a, 1);
        await tick();

        timers
          ..elapse(const Duration(seconds: 1))
          ..elapse(const Duration(seconds: 1));

        expect(a.isReleased, isTrue);
        expect(a.texture, isNull);
        expect(pool.leasedTextures, 0);
        expect(pool.idleTextures, 1);
      },
    );

    test(
      'a texture released during a write idles once the write ends',
      () async {
        await pool.warm(64, 1);
        final a = lease('a');
        writer.pause();
        scheduler.want(a, 1);
        await tick();

        a.release();
        expect(pool.idleTextures, 0, reason: 'its write still runs');

        writer.resume();
        await pumpEventQueue();
        expect(pool.idleTextures, 1);
      },
    );

    test(
      'a lease for a canvas takes a slot even with a texture free',
      () async {
        await pool.warm(64, 1);
        final a = scheduler.acquire('a', 'src', 48, 32, onCanvas: true)!;

        scheduler.want(a, 1, onCanvas: true);
        await tick();

        expect(writer.batches, isEmpty);
        expect(a.sprite, isNotNull);
        expect(pool.idleTextures, 1);
      },
    );

    test('a canvas paint moves a texture lease back to a slot until a sweep '
        'passes without one', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      scheduler.want(a, 1);
      await tick();
      await untilShown();
      expect(a.texture, isNotNull);

      scheduler.want(a, 2, onCanvas: true);
      expect(a.texture, isNull);
      expect(pool.idleTextures, 1);
      await tick();
      expect(renderer.batches.last, [2]);
      expect(a.sprite, isNotNull);

      timers.elapse(const Duration(seconds: 1));
      scheduler.want(a, 3);
      await tick();
      expect(a.sprite, isNotNull, reason: 'painted on a canvas this period');

      timers.elapse(const Duration(seconds: 1));
      scheduler.want(a, 4);
      await tick();
      await untilShown();
      expect(a.texture, isNotNull);
    });

    test('textures switched off send every lease to a slot, and back on '
        'to idle textures', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      scheduler.want(a, 1);
      await tick();
      await untilShown();
      expect(a.texture, isNotNull);

      scheduler.texturesEnabled = false;
      expect(a.texture, isNull);
      scheduler.want(a, 2);
      await tick();
      expect(renderer.batches.last, [2]);
      expect(pool.idleTextures, 1);

      scheduler.texturesEnabled = true;
      scheduler.want(a, 3);
      await tick();
      await untilShown();
      expect(a.texture, isNotNull);
    });

    test('dispose gives every texture back', () async {
      await pool.warm(64, 2);
      lease('a');
      lease('b');

      scheduler.dispose();

      expect(pool.leasedTextures, 0);
      expect(pool.idleTextures, 2);
    });
  });
}
