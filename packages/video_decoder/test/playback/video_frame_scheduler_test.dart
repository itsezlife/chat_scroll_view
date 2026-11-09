import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

import '../support/gated_video_engine.dart';

/// A tiny image per page upload: these tests read the page bytes, not pixels.
Future<ui.Image> _upload(Uint8List pixels, int side) {
  uploadedBytes.add(pixels.length);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return Future.value(image);
}

/// The byte length of every page upload so far, in order.
final List<int> uploadedBytes = [];

const _frameMs = 33;

/// 30 fps, 3 frames: pts 0, 33, 67 ms (the fake's), loop length 100 ms.
const _info = VideoInfo(
  width: 16,
  height: 16,
  duration: Duration(milliseconds: 100),
  frameRate: 30,
  hasAlpha: true,
);

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  late FakeVideoEngine fake;
  late GatedVideoEngine engine;
  late ListFramePageMemory memory;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late VideoFrameScheduler scheduler;
  var time = Duration.zero;

  Future<VideoClip> openClip() async {
    final result = await engine.open(bytes, width: 16, height: 16);
    return (result as VideoClipOpened).clip;
  }

  VideoFrameScheduler build({
    int maxAdvancing = 6,
    int prefetch = 3,
    int budget = 32 * 1024 * 1024,
  }) => VideoFrameScheduler(
    engine: engine,
    atlas: VideoFrameAtlas.create(
      memory: memory,
      budgetBytes: budget,
      upload: _upload,
    ),
    clock: clock,
    maxAdvancing: maxAdvancing,
    prefetch: prefetch,
    startTimer: timers.start,
  );

  /// One clock frame, then the decodes it started.
  Future<void> tick() async {
    time += const Duration(milliseconds: 16);
    ticks.tick(time);
    await pumpEventQueue();
  }

  /// Ticks until the engine has nothing pending, as a few frames pass.
  Future<void> settle([int ticksCount = 8]) async {
    for (var i = 0; i < ticksCount; i++) {
      await tick();
    }
  }

  /// The BGRA pixel at the slot's top left corner, read from page memory.
  List<int> pixelOf(VideoFrameLease lease) {
    final sprite = lease.sprite!;
    final side = memory.sideOf(sprite.pageIndex);
    final page = memory.page(sprite.pageIndex, side: side);
    final at =
        (sprite.source.top.toInt() * side + sprite.source.left.toInt()) * 4;
    return page.sublist(at, at + 4);
  }

  setUp(() {
    time = Duration.zero;
    uploadedBytes.clear();
    fake = FakeVideoEngine()..accept(bytes, _info, frameCount: 3);
    engine = GatedVideoEngine(fake);
    memory = ListFramePageMemory();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = build();
  });
  tearDown(() async {
    scheduler.dispose();
    clock.dispose();
    await fake.dispose();
  });

  group('VideoFrameScheduler', () {
    test('follows the clock only while a lease exists', () async {
      expect(ticks.isRunning, isFalse);

      final lease = scheduler.acquire('a', await openClip())!;
      expect(ticks.isRunning, isTrue);

      lease.release();
      expect(ticks.isRunning, isFalse);
    });

    test('decodes ahead and shows the frame the clip time names', () async {
      final lease = scheduler.acquire('a', await openClip())!;
      scheduler.want(lease, Duration.zero);
      await settle();
      expect(lease.sprite, isNotNull);
      // Frame 0 of the fake: blue 0, green 0, red 0, alpha 200.
      expect(pixelOf(lease), [0, 0, 0, 200]);

      scheduler.want(lease, const Duration(milliseconds: _frameMs + 1));
      await settle();

      // Index 1 of the fake: blue 16, green 8.
      expect(pixelOf(lease), [16, 8, 0, 200]);
    });

    test(
      'keeps the ring to the prefetch depth and one decode in flight',
      () async {
        final lease = scheduler.acquire('a', await openClip())!;
        scheduler.want(lease, Duration.zero);

        await settle(20);

        // The clock stood still: frame 0 shown, then 3 ahead (two frames, the
        // end of the stream, and frame 0 of the next pass) and it stops asking.
        expect(engine.nextFrameCalls.values.single, lessThanOrEqualTo(5));
        expect(engine.maxInFlightPerClip, 1);
        expect(scheduler.bufferedBytes, lessThanOrEqualTo(5 * 16 * 16 * 4));
      },
    );

    test('loops by rewinding at the end of the stream', () async {
      final lease = scheduler.acquire('a', await openClip())!;
      // 250 ms is in the third pass of a 100 ms clip, at 50 ms: pts 33.
      for (var ms = 0; ms <= 250; ms += 25) {
        scheduler.want(lease, Duration(milliseconds: ms));
        await tick();
      }
      await settle();

      expect(pixelOf(lease), [16, 8, 0, 200]);
      expect(engine.rewinds, greaterThanOrEqualTo(3));
    });

    test(
      'more clips than slots: every clip is shown, none is frozen',
      () async {
        scheduler.dispose();
        scheduler = build(maxAdvancing: 6);
        final leases = <VideoFrameLease>[];
        for (var i = 0; i < 10; i++) {
          leases.add(scheduler.acquire('k$i', await openClip())!);
        }
        for (var ms = 0; ms <= 400; ms += 16) {
          for (final lease in leases) {
            scheduler.want(lease, Duration(milliseconds: ms));
          }
          await tick();
        }

        expect(leases.where((l) => l.sprite == null), isEmpty);
      },
    );

    test('a clip passed over keeps its own clock', () async {
      scheduler.dispose();
      scheduler = build(maxAdvancing: 1);
      final first = scheduler.acquire('first', await openClip())!;
      final second = scheduler.acquire('second', await openClip())!;
      for (var ms = 0; ms <= 80; ms += 16) {
        scheduler.want(first, Duration(milliseconds: ms));
        scheduler.want(second, Duration(milliseconds: ms));
        await tick();
      }
      await settle();

      // 80 ms in: both name frame 2 (pts 67), whichever had the slot.
      expect(pixelOf(first), [32, 16, 0, 200]);
      expect(pixelOf(second), [32, 16, 0, 200]);
    });

    group('under a slow engine', () {
      late List<VideoFrameLease> leases;
      late Map<VideoFrameLease, List<int>> changes;

      /// Paints every lease every tick for [ms], lets [perTick] decodes finish
      /// per tick, and writes down in which tick each lease's frame changed.
      Future<void> play({
        required int clips,
        required int? perTick,
        required int cap,
        int ms = 2000,
      }) async {
        scheduler.dispose();
        scheduler = build(maxAdvancing: cap);
        leases = [
          for (var i = 0; i < clips; i++)
            scheduler.acquire('k$i', await openClip())!,
        ];
        changes = {for (final l in leases) l: <int>[]};
        final shown = <VideoFrameLease, List<int>>{};
        if (perTick != null) engine.hold();
        for (var step = 0; step * 16 <= ms; step++) {
          for (final lease in leases) {
            scheduler.want(lease, Duration(milliseconds: step * 16));
          }
          await tick();
          if (perTick != null) engine.release(perTick);
          await pumpEventQueue();
          for (final lease in leases) {
            if (lease.sprite == null) continue;
            final now = pixelOf(lease);
            if (shown[lease]?.join() != now.join()) changes[lease]!.add(step);
            shown[lease] = now;
          }
        }
      }

      test('no visible clip waits longer than the bound for a frame', () async {
        // 8 clips need 240 frames a second; the engine finishes 2 per 16 ms.
        await play(clips: 8, perTick: 2, cap: 3);

        for (final lease in leases) {
          final steps = changes[lease]!;
          expect(steps, isNotEmpty);
          var longest = steps.first;
          for (var i = 1; i < steps.length; i++) {
            longest = longest > steps[i] - steps[i - 1]
                ? longest
                : steps[i] - steps[i - 1];
          }
          // 250 ms is 16 ticks of 16 ms; a few more for the engine's queue.
          expect(longest * 16, lessThanOrEqualTo(400), reason: '$lease');
        }
        expect(engine.maxInFlightPerClip, 1);
      });

      test('slots short, not decodes: the newest update most, the oldest '
          'still update', () async {
        await play(clips: 8, perTick: null, cap: 2);

        final newest = changes[leases.last]!.length;
        final oldest = changes[leases.first]!.length;
        expect(oldest, greaterThanOrEqualTo(2000 ~/ 250));
        expect(newest, greaterThan(oldest));
      });
    });

    test('a cap raised at run time serves the clips it held back', () async {
      scheduler.dispose();
      scheduler = build(maxAdvancing: 1);
      final leases = [
        for (var i = 0; i < 4; i++) scheduler.acquire('k$i', await openClip())!,
      ];
      engine.hold();
      for (var ms = 0; ms < 48; ms += 16) {
        for (final lease in leases) {
          scheduler.want(lease, Duration(milliseconds: ms));
        }
        await tick();
      }
      expect(
        engine.inFlight.values.where((n) => n > 0),
        hasLength(lessThan(4)),
      );

      scheduler.maxAdvancing = 4;
      for (final lease in leases) {
        scheduler.want(lease, const Duration(milliseconds: 64));
      }
      await tick();

      expect(engine.inFlight.values.where((n) => n > 0), hasLength(4));
      engine.release();
    });

    test(
      'clips that are not painted take no slot and then lose the lease',
      () async {
        scheduler.dispose();
        scheduler = build(maxAdvancing: 2);
        final live = [
          for (var i = 0; i < 2; i++)
            scheduler.acquire('live$i', await openClip())!,
        ];
        final gone = [
          for (var i = 0; i < 2; i++)
            scheduler.acquire('gone$i', await openClip())!,
        ];
        // All painted once, then only the live ones are.
        for (final lease in [...live, ...gone]) {
          scheduler.want(lease, Duration.zero);
        }
        await tick();
        engine.nextFrameCalls.clear();
        var played = Duration.zero;
        for (var i = 0; i < 40; i++) {
          played += const Duration(milliseconds: 16);
          for (final lease in live) {
            scheduler.want(lease, played);
          }
          await tick();
          timers.elapse(const Duration(milliseconds: 100));
        }

        expect(gone.every((l) => l.isReleased), isTrue);
        expect(live.every((l) => !l.isReleased && l.sprite != null), isTrue);
        expect(scheduler.leaseCount, 2);
      },
    );

    test('a clip that is not painted for a while is not served', () async {
      scheduler.dispose();
      scheduler = build(maxAdvancing: 1);
      final staleClip = await openClip();
      final stale = scheduler.acquire('stale', staleClip)!;
      final live = scheduler.acquire('live', await openClip())!;
      scheduler.want(stale, Duration.zero);
      await tick();
      engine.nextFrameCalls.clear();
      var played = Duration.zero;
      var callsAtWindowEnd = 0;
      for (var i = 0; i < 30; i++) {
        played += const Duration(milliseconds: 16);
        scheduler.want(live, played);
        await tick();
        // The window is 150 ms: ten ticks after its one paint.
        if (i == 10)
          callsAtWindowEnd = engine.nextFrameCalls[staleClip.id] ?? 0;
      }

      // Past the window the stale clip asks the engine for nothing more.
      expect(engine.nextFrameCalls[staleClip.id] ?? 0, callsAtWindowEnd);
      expect(live.sprite, isNotNull);
    });

    test('a slow engine skips to the newest ready frame', () async {
      final lease = scheduler.acquire('a', await openClip())!;
      engine.hold();
      scheduler.want(lease, Duration.zero);
      await tick();
      // The clock runs 90 ms ahead while no frame has come back.
      scheduler.want(lease, const Duration(milliseconds: 90));
      await tick();
      expect(lease.sprite, isNull);

      // Three frames land between two clock frames.
      engine.release();
      await pumpEventQueue();
      await tick();

      // Frame 2 at once; frames 0 and 1 were never shown.
      expect(pixelOf(lease), [32, 16, 0, 200]);
    });

    test(
      'a frame that arrives after release is dropped, and bytes return to zero',
      () async {
        final lease = scheduler.acquire('a', await openClip())!;
        engine.hold();
        scheduler.want(lease, Duration.zero);
        await tick();
        expect(scheduler.bufferedBytes, greaterThan(0));

        lease.release();
        engine.release();
        await pumpEventQueue();

        expect(scheduler.bufferedBytes, 0);
      },
    );

    test('releasing everything returns the pool bytes to zero', () async {
      final lease = scheduler.acquire('a', await openClip())!;
      scheduler.want(lease, Duration.zero);
      await settle();
      expect(scheduler.residentBytes, greaterThan(0));

      lease.release();
      expect(scheduler.bufferedBytes, 0);
      scheduler.releaseIdle();

      expect(scheduler.residentBytes, 0);
    });

    test('a lone clip uploads its own cell, not a page of four', () async {
      final lease = scheduler.acquire('a', await openClip())!;
      scheduler.want(lease, Duration.zero);
      await settle();

      // A 16 px clip lives in a 64 px cell on a 64 px page, and the upload
      // stops at its last row: 16 rows of 64 pixels.
      expect(uploadedBytes, isNotEmpty);
      expect(uploadedBytes.toSet(), {64 * 16 * 4});
    });

    group('frame step', () {
      // 60 fps, 8 frames: pts 0, 17, 33, ... 117 ms; the fake's blue is 16
      // times the frame index.
      final bytes60 = Uint8List.fromList([6, 0]);
      const info60 = VideoInfo(
        width: 16,
        height: 16,
        duration: Duration(milliseconds: 133),
        frameRate: 60,
        hasAlpha: true,
      );

      /// The frame indices shown over two passes, painted every clock frame.
      Future<Set<int>> shownFrames({required int frameStep}) async {
        fake.accept(bytes60, info60, frameCount: 8);
        final opened = await engine.open(bytes60, width: 16, height: 16);
        final lease = scheduler.acquire('a', (opened as VideoClipOpened).clip)!;
        final shown = <int>{};
        for (var ms = 0; ms <= 260; ms += 16) {
          scheduler.want(
            lease,
            Duration(milliseconds: ms),
            frameStep: frameStep,
          );
          await tick();
          if (lease.sprite != null) shown.add(pixelOf(lease).first ~/ 16);
        }
        return shown;
      }

      test('a step of two shows only every second decoded frame', () async {
        final shown = await shownFrames(frameStep: 2);

        expect(shown, isNotEmpty);
        expect(shown.where((frame) => frame.isOdd), isEmpty);
        expect(shown, containsAll([0, 2, 4, 6]));
      });

      test('a step of one shows the odd frames too', () async {
        final shown = await shownFrames(frameStep: 1);

        expect(shown.where((frame) => frame.isOdd), isNotEmpty);
      });
    });

    test('a tick uploads the cells that moved, not their neighbours', () async {
      scheduler.dispose();
      scheduler = build(maxAdvancing: 1);
      final clip = await openClip();
      final frozen = scheduler.acquire('frozen', clip)!;
      final moving = scheduler.acquire('moving', clip)!;
      scheduler.want(frozen, Duration.zero);
      scheduler.want(moving, Duration.zero);
      await settle();
      uploadedBytes.clear();

      scheduler.want(moving, const Duration(milliseconds: _frameMs + 1));
      await settle();

      // Only the newest lease advances; its upload is its own page's 16 rows.
      expect(uploadedBytes, isNotEmpty);
      expect(uploadedBytes.every((bytes) => bytes == 64 * 16 * 4), isTrue);
    });

    test(
      'clock frames that name the same video frame upload nothing',
      () async {
        final lease = scheduler.acquire('a', await openClip())!;
        scheduler.want(lease, Duration.zero);
        await settle();
        final settled = uploadedBytes.length;
        expect(settled, greaterThan(0));

        // A 30 fps clip on a faster display: the clock ticks, the clip time
        // stays inside frame 0's interval, so there is no new frame to show.
        for (var i = 0; i < 6; i++) {
          scheduler.want(lease, Duration(milliseconds: i));
          await tick();
        }

        expect(uploadedBytes.length, settled);
      },
    );

    test('a full pool answers null so the caller keeps its still', () async {
      scheduler.dispose();
      // One 64 px page of 2x2 cells needs 128*128*4 bytes; fit exactly one.
      scheduler = build(budget: 128 * 128 * 4);
      final clip = await openClip();
      final leases = [
        for (var i = 0; i < 4; i++) scheduler.acquire('k$i', clip),
      ];
      expect(leases.whereType<VideoFrameLease>(), hasLength(4));
      expect(scheduler.acquire('k4', clip), isNull);
    });

    group('a full pool', () {
      late List<VideoFrameLease> leases;

      setUp(() async {
        scheduler.dispose();
        scheduler = build(budget: 128 * 128 * 4);
        final clip = await openClip();
        leases = [for (var i = 0; i < 4; i++) scheduler.acquire('k$i', clip)!];
      });

      /// Ticks for [ms] while [painted] are wanted every frame.
      Future<void> play(int ms, List<VideoFrameLease> painted) async {
        for (var t = 0; t < ms; t += 16) {
          for (final lease in painted) {
            scheduler.want(lease, Duration(milliseconds: t));
          }
          await tick();
        }
      }

      test('takes the slot of the clip painted least recently', () async {
        await play(48, leases);
        await play(48, leases.sublist(1)); // k0 leaves first
        await play(200, leases.sublist(2)); // then k1

        final extra = scheduler.acquire('extra', await openClip());

        expect(extra, isNotNull);
        expect(leases[0].isReleased, isTrue);
        expect(leases.skip(1).map((l) => l.isReleased), [false, false, false]);
      });

      test('never takes a clip painted within the visible window', () async {
        await play(200, leases.sublist(1));
        scheduler.want(leases[0], Duration.zero);
        await tick();
        await tick();

        expect(scheduler.acquire('extra', await openClip()), isNull);
        expect(leases.map((l) => l.isReleased), everyElement(isFalse));
      });

      test('never takes a kept clip, however long it went unpainted', () async {
        for (final lease in leases) {
          lease.kept = true;
        }
        await play(500, const []);

        expect(scheduler.acquire('extra', await openClip()), isNull);
        expect(leases.map((l) => l.isReleased), everyElement(isFalse));
      });
    });

    group('a clip whose paintable left the screen', () {
      test('ends its lease once the frame is over', () async {
        final lease = scheduler.acquire('a', await openClip())!;
        lease.releaseUnlessPainted();
        expect(lease.isReleased, isFalse);

        timers.elapse(Duration.zero);
        expect(lease.isReleased, isTrue);
      });

      test('keeps it when painted in that frame, or kept', () async {
        final painted = scheduler.acquire('a', await openClip())!;
        final kept = scheduler.acquire('b', await openClip())!..kept = true;
        painted.releaseUnlessPainted();
        kept.releaseUnlessPainted();
        scheduler.want(painted, Duration.zero);

        timers.elapse(Duration.zero);
        expect(painted.isReleased, isFalse);
        expect(kept.isReleased, isFalse);
      });
    });

    test('a decode failure fails the lease', () async {
      final clip = await openClip();
      final lease = scheduler.acquire('a', clip)!;
      // A closed clip cannot rewind, which is where every lease starts.
      await engine.close(clip);
      scheduler.want(lease, Duration.zero);
      await settle();

      expect(lease.isFailed, isTrue);
    });

    test('hold keeps the current frame and stops decoding', () async {
      final lease = scheduler.acquire('a', await openClip())!;
      scheduler.want(lease, Duration.zero);
      await settle();
      final calls = engine.nextFrameCalls.values.single;

      lease.hold();
      scheduler.want(lease, const Duration(seconds: 5));
      await settle();

      expect(engine.nextFrameCalls.values.single, calls);
      expect(lease.sprite, isNotNull);
    });
  });
}
