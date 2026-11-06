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
      'at most maxAdvancing clips advance; the least recently leased hold',
      () async {
        scheduler.dispose();
        scheduler = build(maxAdvancing: 6);
        final leases = <VideoFrameLease>[];
        for (var i = 0; i < 10; i++) {
          leases.add(scheduler.acquire('k$i', await openClip())!);
        }
        for (final lease in leases) {
          scheduler.want(lease, Duration.zero);
        }
        await settle();

        final shown = leases.where((l) => l.sprite != null).toList();
        expect(shown, hasLength(6));
        // The newest six.
        expect(shown, leases.sublist(4));
      },
    );

    test(
      'a held clip resumes when a slot frees, from where it stopped',
      () async {
        scheduler.dispose();
        scheduler = build(maxAdvancing: 1);
        final older = scheduler.acquire('old', await openClip())!;
        final newer = scheduler.acquire('new', await openClip())!;
        for (var ms = 0; ms <= 100; ms += 20) {
          scheduler.want(older, Duration(milliseconds: ms));
          scheduler.want(newer, Duration(milliseconds: ms));
          await tick();
        }
        expect(older.sprite, isNull);

        newer.release();
        scheduler.want(older, const Duration(milliseconds: 120));
        await settle();

        expect(older.sprite, isNotNull);
      },
    );

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
