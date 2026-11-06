import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// Two 128 px pages: four 64 px cells each.
const _budget = 2 * 128 * 128 * 4;

/// A tiny image per upload: the scheduler's tests look at what was rendered
/// and at whether a sprite exists, not at pixels.
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
  late FrameAtlas<Object> atlas;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late LottieFrameScheduler scheduler;
  var time = Duration.zero;

  /// One clock frame, 16 ms after the last.
  void tick() {
    time += const Duration(milliseconds: 16);
    ticks.tick(time);
  }

  LottieFrameScheduler build({int budget = _budget}) {
    atlas = FrameAtlas<Object>(
      renderer: renderer,
      memory: ListFramePageMemory(pageSide: 128),
      budgetBytes: budget,
      sizeClasses: const [64],
      upload: _upload,
    );
    return LottieFrameScheduler(
      atlas: atlas,
      clock: clock,
      startTimer: timers.start,
    );
  }

  setUp(() {
    time = Duration.zero;
    renderer = FakeFrameRenderer();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = build();
  });
  tearDown(() {
    scheduler.dispose();
    clock.dispose();
  });

  LottieFrameLease lease(String key, {Object source = 'src'}) =>
      scheduler.acquire(key, source, 48, 48)!;

  group('LottieFrameScheduler', () {
    test('follows the clock only while a lease exists', () {
      expect(ticks.isRunning, isFalse);

      final a = lease('a');
      final b = lease('b');
      expect(ticks.isRunning, isTrue);
      expect(ticks.starts, 1);

      a.release();
      expect(ticks.isRunning, isTrue, reason: 'b is still leased');
      b.release();
      expect(ticks.isRunning, isFalse);
    });

    test('sends one batch of every want on a tick', () async {
      final leases = [
        for (final k in ['a', 'b', 'c']) lease(k),
      ];
      scheduler.want(leases[0], 3);
      scheduler.want(leases[1], 5);
      scheduler.want(leases[2], 7);

      tick();
      await pumpEventQueue();

      expect(renderer.batches, [
        [3, 5, 7],
      ]);
      expect(leases[0].sprite, isNotNull);
    });

    test('does not render a frame it already rendered', () async {
      final a = lease('a');
      scheduler.want(a, 2);
      tick();
      await pumpEventQueue();

      scheduler.want(a, 2);
      tick();
      await pumpEventQueue();

      expect(renderer.batches, hasLength(1));
    });

    test('coalesces wants made while a batch is in flight', () async {
      final a = lease('a');
      renderer.pause();
      scheduler.want(a, 1);
      tick();
      scheduler.want(a, 2);
      tick();
      scheduler.want(a, 3);
      tick();
      renderer.resume();
      await pumpEventQueue();
      expect(renderer.batches, [
        [1],
      ]);

      tick();
      await pumpEventQueue();
      expect(renderer.batches, [
        [1],
        [3],
      ]);
    });

    test('renders nothing while the clock is paused', () async {
      final a = lease('a');
      scheduler.want(a, 4);
      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);

      tick();
      await pumpEventQueue();
      expect(renderer.batches, isEmpty);

      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: false);
      tick();
      await pumpEventQueue();
      expect(renderer.batches, [
        [4],
      ]);
    });

    test('answers null when the pool is full, without throwing', () {
      scheduler.dispose();
      scheduler = build(budget: 128 * 128 * 4);
      final held = [for (var i = 0; i < 4; i++) lease('k$i')];

      expect(scheduler.acquire('extra', 'src', 48, 48), isNull);
      expect(held, hasLength(4));
    });

    test('releases a lease nobody wanted for a sweep, keeping its entry', () {
      final idle = lease('idle');
      final busy = lease('busy');
      scheduler.want(idle, 1);
      scheduler.want(busy, 1);

      timers.elapse(const Duration(seconds: 1));
      scheduler.want(busy, 2);
      timers.elapse(const Duration(seconds: 1));

      expect(idle.isReleased, isTrue);
      expect(busy.isReleased, isFalse);
      expect(atlas.isResident('idle'), isTrue, reason: 'evictable, not gone');
    });

    test('has a sweep timer only while leases exist', () {
      expect(timers.pending, 0);

      final a = lease('a');
      final b = lease('b');
      expect(timers.pending, 1, reason: 'one sweep for every lease');

      a.release();
      expect(timers.pending, 1);
      b.release();
      expect(timers.pending, 0);
    });

    test('keeps sweeping while a lease survives', () {
      final a = lease('a');
      for (var i = 0; i < 3; i++) {
        scheduler.want(a, i);
        timers.elapse(const Duration(seconds: 1));
      }
      expect(a.isReleased, isFalse);
      expect(timers.pending, 1);
    });

    test('marks a failed job and stops asking for it', () async {
      final bad = lease('bad', source: FakeFrameRenderer.rejected);
      final good = lease('good');
      scheduler.want(bad, 1);
      scheduler.want(good, 1);
      tick();
      await pumpEventQueue();

      expect(bad.isFailed, isTrue);
      expect(good.isFailed, isFalse);

      scheduler.want(bad, 2);
      scheduler.want(good, 2);
      tick();
      await pumpEventQueue();
      expect(renderer.batches.last, [2], reason: 'only the good one');
      expect(renderer.batches, hasLength(2));
    });

    test('dispose releases every lease and stops following', () {
      final a = lease('a');
      final b = lease('b');

      scheduler.dispose();

      expect(a.isReleased, isTrue);
      expect(b.isReleased, isTrue);
      expect(ticks.isRunning, isFalse);
      expect(timers.pending, 0);
    });

    test('refuses a second lease on a key', () {
      lease('a');
      expect(() => lease('a'), throwsStateError);
    });
  });
}
