import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:catalog_assets/src/playback/playback_policy.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _small = AssetSpec(pixelWidth: 100, pixelHeight: 100);
const _large = AssetSpec(pixelWidth: 512, pixelHeight: 512);

Duration _ms(int ms) => Duration(milliseconds: ms);

final class _Target implements PlaybackTarget {
  _Target(this.frameInterval);

  @override
  final Duration frameInterval;

  final List<Duration> ticks = [];

  @override
  void tick(Duration now) => ticks.add(now);
}

void main() {
  late ManualPlaybackTickSource source;
  late PlaybackClock clock;

  setUp(() {
    source = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: source);
  });
  tearDown(() => clock.dispose());

  group('PlaybackPolicy', () {
    test('caps a small asset at 30 fps and a large one at 60', () {
      const policy = PlaybackPolicy();

      expect(policy.fpsCapFor(_small), 30);
      expect(policy.fpsCapFor(_large), 60);
      expect(
        policy.frameIntervalFor(_small),
        const Duration(microseconds: 33333),
      );
    });

    test('decides by the longer edge', () {
      const policy = PlaybackPolicy();

      expect(
        policy.fpsCapFor(const AssetSpec(pixelWidth: 10, pixelHeight: 400)),
        60,
      );
      expect(
        policy.fpsCapFor(const AssetSpec(pixelWidth: 270, pixelHeight: 270)),
        30,
      );
    });
  });

  group('the clock', () {
    test('asks the engine for frames only while something plays', () {
      expect(source.isRunning, isFalse);

      final target = _Target(_ms(16));
      clock.register(target);
      expect(source.isRunning, isTrue);

      clock.unregister(target);
      expect(source.isRunning, isFalse);
    });

    test('now follows the last frame timestamp', () {
      clock.register(_Target(_ms(16)));

      source.tick(_ms(100));

      expect(clock.now, _ms(100));
    });

    test('advances every target together on one frame', () {
      final a = _Target(_ms(16));
      final b = _Target(_ms(16));
      clock
        ..register(a)
        ..register(b);

      source.tick(_ms(16));

      expect(a.ticks, [_ms(16)]);
      expect(b.ticks, [_ms(16)]);
    });

    test('a 30 fps target skips frames of a 60 fps display', () {
      final target = _Target(const PlaybackPolicy().frameIntervalFor(_small));
      clock.register(target);

      for (var frame = 1; frame <= 6; frame++) {
        source.tick(Duration(microseconds: frame * 16667));
      }

      // 16.7 ms is under the 33.3 ms cap (minus slack): every second frame.
      expect(target.ticks, hasLength(3));
    });

    test('a 30 fps target runs every fourth frame of a 120 Hz display', () {
      final target = _Target(const PlaybackPolicy().frameIntervalFor(_small));
      clock.register(target);

      for (var frame = 1; frame <= 8; frame++) {
        source.tick(Duration(microseconds: frame * 8333));
      }

      expect(target.ticks, hasLength(2));
    });

    test('a target registered later is advanced on the next frame', () {
      clock.register(_Target(_ms(16)));
      source.tick(_ms(16));
      final late = _Target(_ms(16));

      clock.register(late);
      source.tick(_ms(32));

      expect(late.ticks, [_ms(32)]);
    });

    test('a target unregistered by an earlier one in the frame is skipped', () {
      final victim = _Target(_ms(16));
      clock
        ..register(_UnregisteringTarget(clock, victim))
        ..register(victim);

      source.tick(_ms(16));

      expect(victim.ticks, isEmpty);
    });
  });

  group('pause layers', () {
    test('any set layer stops the frames and clearing all resumes them', () {
      final target = _Target(_ms(16));
      clock.register(target);

      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);
      expect(clock.isPaused, isTrue);
      expect(source.isRunning, isFalse);

      clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: false);
      expect(clock.isPaused, isTrue, reason: 'route is still moving');
      expect(source.isRunning, isFalse);

      clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
      expect(clock.isPaused, isFalse);
      expect(source.isRunning, isTrue);
    });

    test('lists the layers that are set', () {
      clock
        ..setPaused(PlaybackPauseLayer.lowPower, paused: true)
        ..setPaused(PlaybackPauseLayer.surfaceHidden, paused: true);

      expect(clock.pausedLayers, {
        PlaybackPauseLayer.lowPower,
        PlaybackPauseLayer.surfaceHidden,
      });
    });

    test('a layer the policy does not pause on leaves playback running', () {
      final custom = PlaybackClock(
        ticks: ManualPlaybackTickSource(),
        policy: const PlaybackPolicy(
          pausingLayers: {PlaybackPauseLayer.surfaceHidden},
        ),
      )..setPaused(PlaybackPauseLayer.lowPower, paused: true);
      addTearDown(custom.dispose);

      expect(custom.isPaused, isFalse);
    });

    test('setting a layer twice then clearing once clears it', () {
      clock
        ..setPaused(PlaybackPauseLayer.lowPower, paused: true)
        ..setPaused(PlaybackPauseLayer.lowPower, paused: true)
        ..setPaused(PlaybackPauseLayer.lowPower, paused: false);

      expect(clock.isPaused, isFalse);
    });
  });

  group('disposal', () {
    test('stops the frames and ignores later registrations', () {
      clock.register(_Target(_ms(16)));

      clock.dispose();
      final target = _Target(_ms(16));
      clock.register(target);

      expect(source.isRunning, isFalse);
      source.tick(_ms(16));
      expect(target.ticks, isEmpty);
    });
  });
}

final class _UnregisteringTarget implements PlaybackTarget {
  _UnregisteringTarget(this.clock, this.other);

  final PlaybackClock clock;
  final PlaybackTarget other;

  @override
  Duration get frameInterval => const Duration(milliseconds: 16);

  @override
  void tick(Duration now) => clock.unregister(other);
}
