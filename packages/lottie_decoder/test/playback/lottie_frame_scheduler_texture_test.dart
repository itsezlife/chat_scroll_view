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

  // Posts frames [from] to [from] + 2, one a tick: a texture is shown after
  // three posts of its lease.
  Future<void> postThree(LottieFrameLease lease, int from) async {
    for (var frame = from; frame < from + 3; frame++) {
      scheduler.want(lease, frame);
      await tick();
    }
  }

  setUp(() {
    time = Duration.zero;
    renderer = FakeFrameRenderer();
    host = FakeFrameTextureHost();
    // Released textures are leased again at once here; the pool's own tests
    // cover the reuse delay.
    pool = FrameTexturePool(
      host: host,
      sizeClasses: const [64],
      reuseDelay: Duration.zero,
    );
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

    test('exposes the texture only once three frames were posted', () async {
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
      // The texture may still queue frames of the asset that held it, which
      // the engine would show first.
      expect(a.texture, isNull, reason: 'one post');
      scheduler.want(a, 2);
      await tick();
      expect(a.texture, isNull, reason: 'two posts');
      scheduler.want(a, 3);
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

      await postThree(a, 3);
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

    test('a slow write of one lease never delays the next frame of '
        'another', () async {
      await pool.warm(64, 2);
      final slow = lease('slow', source: 'slow');
      final fast = lease('fast', source: 'fast');
      scheduler
        ..want(slow, 1)
        ..want(fast, 1);
      await tick();
      int idOf(Object source) => writer.batches
          .expand((batch) => batch)
          .firstWhere((job) => job.source == source)
          .texture
          .id;
      final slowId = idOf('slow');
      final fastId = idOf('fast');
      writer.batches.clear();

      writer.hold(slowId);
      scheduler
        ..want(slow, 2)
        ..want(fast, 2);
      await tick();
      for (var frame = 3; frame <= 5; frame++) {
        scheduler
          ..want(slow, frame)
          ..want(fast, frame);
        await tick();
      }

      final written = [
        for (final batch in writer.batches)
          for (final job in batch) (job.texture.id, job.frame),
      ];
      expect(
        [
          for (final (id, frame) in written)
            if (id == fastId) frame,
        ],
        [2, 3, 4, 5],
        reason: 'one frame a tick while the other write is held',
      );
      expect(written.where((w) => w.$1 == slowId), isEmpty);

      writer.letGo(slowId);
      await pumpEventQueue();
      await tick();
      expect(
        [
          for (final batch in writer.batches)
            for (final job in batch)
              if (job.texture.id == slowId) job.frame,
        ],
        [2, 5],
        reason: 'the slow one wrote its frame, then only the latest want',
      );
    });

    test('a slow page batch never delays a texture lease', () async {
      await pool.warm(64, 1);
      final onTexture = lease('texture');
      final onSlot = lease('slot');
      expect(pool.idleTextures, 0);

      renderer.pause();
      for (var frame = 1; frame <= 3; frame++) {
        scheduler
          ..want(onTexture, frame)
          ..want(onSlot, frame);
        await tick();
      }

      expect(
        [for (final batch in writer.batches) batch.single.frame],
        [1, 2, 3],
      );
      expect(renderer.batches, isEmpty, reason: 'the page batch is held');
      renderer.resume();
      await pumpEventQueue();
      expect(renderer.batches, [
        [1],
      ]);
    });

    test('a lock that fails skips the frame and asks it again', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      final id = host.liveIds.single;
      await postThree(a, 1);

      writer.outcomeOf[id] = TextureFrameOutcome.notLocked;
      scheduler.want(a, 4);
      await tick();
      expect(a.texture?.id, id, reason: 'it keeps its previous frame');

      writer.outcomeOf.remove(id);
      await tick();
      expect(
        [for (final batch in writer.batches) batch.single.frame],
        [1, 2, 3, 4, 4],
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

    test('a kept lease keeps its texture and frame through the sweeps, '
        'renders nothing, and is swept once it is let go', () async {
      await pool.warm(64, 2);
      final a = lease('a');
      await postThree(a, 1);
      final shown = a.texture;
      expect(shown, isNotNull);
      final writes = writer.batches.length;

      a.kept = true;
      final b = lease('b');
      for (var i = 0; i < 3; i++) {
        timers.elapse(const Duration(seconds: 1));
        scheduler.want(b, i);
        await tick();
      }

      expect(a.isReleased, isFalse);
      expect(a.texture, shown);
      expect(
        writer.batches.skip(writes).expand((batch) => batch),
        everyElement(
          isA<TextureFrameJob>().having(
            (job) => job.texture,
            'texture',
            isNot(shown),
          ),
        ),
      );

      a.kept = false;
      timers
        ..elapse(const Duration(seconds: 1))
        ..elapse(const Duration(seconds: 1));
      expect(a.isReleased, isTrue);
    });

    test(
      'a kept lease on a slot stays there while textures are free',
      () async {
        final a = lease('a');
        scheduler.want(a, 1);
        await tick();
        expect(a.sprite, isNotNull);
        final renders = renderer.batches.length;

        a.kept = true;
        await pool.warm(64, 1);
        await tick();
        await tick();

        expect(a.sprite, isNotNull);
        expect(renderer.batches, hasLength(renders));
        expect(writer.batches, isEmpty);
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
      await postThree(a, 1);
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
      await postThree(a, 4);
      expect(a.texture, isNotNull);
    });

    test('textures switched off send every lease to a slot, and back on '
        'to idle textures', () async {
      await pool.warm(64, 1);
      final a = lease('a');
      await postThree(a, 1);
      expect(a.texture, isNotNull);

      scheduler.texturesEnabled = false;
      expect(a.texture, isNull);
      scheduler.want(a, 2);
      await tick();
      expect(renderer.batches.last, [2]);
      expect(pool.idleTextures, 1);

      scheduler.texturesEnabled = true;
      await postThree(a, 3);
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
