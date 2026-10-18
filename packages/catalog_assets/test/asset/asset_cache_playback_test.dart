import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ContentKey.document('anim-1');
const _small = AssetSpec(pixelWidth: 100, pixelHeight: 100);
const _large = AssetSpec(pixelWidth: 512, pixelHeight: 512);
const _plays = AssetProfile(animate: true);

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ticks),
    );
  });
  tearDown(() => scope.dispose());

  AssetBinding animated({
    AssetSpec spec = _large,
    AssetProfile profile = _plays,
    ContentKey key = _key,
  }) {
    final binding = scope.attach(key, spec, profile);
    producer.last.advance(
      AssetStage.full,
      tier: AssetTier.animated,
      animated: true,
    );
    return binding;
  }

  group('gating: profile animate AND visible', () {
    test('an animated binding plays and asks the engine for frames', () {
      final binding = animated();

      expect(binding.isPlaying, isTrue);
      expect(ticks.isRunning, isTrue);
    });

    test('a profile that does not animate costs no ticks', () {
      final binding = animated(profile: const AssetProfile());

      expect(binding.isPlaying, isFalse);
      expect(ticks.isRunning, isFalse);
    });

    test('a still paintable costs no ticks even for an animating profile', () {
      final binding = scope.attach(_key, _large, _plays);
      producer.last.advance(AssetStage.full);

      expect(binding.isPlaying, isFalse);
      expect(ticks.isRunning, isFalse);
    });

    test('nothing plays before the animated stage exists', () {
      final binding = scope.attach(_key, _large, _plays);
      producer.last.advance(AssetStage.placeholder);

      expect(binding.isPlaying, isFalse);
    });

    test('an invisible binding stays attached but is not advanced', () {
      final binding = animated();

      binding.visible = false;

      expect(binding.isPlaying, isFalse);
      expect(ticks.isRunning, isFalse);
      expect(scope.isAttached(_key, _large), isTrue);

      binding.visible = true;
      expect(binding.isPlaying, isTrue);
      expect(ticks.isRunning, isTrue);
    });

    test('detaching stops the ticks', () {
      final binding = animated();

      binding.detach();

      expect(ticks.isRunning, isFalse);
    });
  });

  group('the shared clock', () {
    test('a tick signals every playing binding, once per frame', () {
      final a = animated();
      final b = animated(key: const ContentKey.document('anim-2'));
      var heardA = 0;
      var heardB = 0;
      a.addListener(() => heardA++);
      b.addListener(() => heardB++);

      ticks.tick(_ms(16));

      expect(heardA, 1);
      expect(heardB, 1);
    });

    test('painting uses the time of the last tick', () {
      final binding = animated();
      final paintable = binding.paintable as FakeAssetPaintable;
      ticks.tick(_ms(48));

      final recorder = PictureRecorder();
      binding.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 8, 8));
      recorder.endRecording().dispose();

      expect(paintable.paints.single.context.time, _ms(48));
    });

    test('a profile that does not animate paints at one time, however the '
        'clock moves, so it shows one frame', () {
      // Something else keeps the clock running.
      animated(key: const ContentKey.document('playing'));
      final still = animated(profile: const AssetProfile());
      final paintable = still.paintable as FakeAssetPaintable;
      void paint() {
        final recorder = PictureRecorder();
        still.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 8, 8));
        recorder.endRecording().dispose();
      }

      ticks.tick(_ms(16));
      paint();
      ticks.tick(_ms(480));
      paint();

      expect(paintable.paints, hasLength(2));
      expect(
        paintable.paints.last.context.time,
        paintable.paints.first.context.time,
      );
    });

    test('a still surface and a playing one of the same entry say which '
        'they are when they paint', () {
      final playing = animated();
      final still = scope.attach(_key, _large, const AssetProfile());
      final paintable = playing.paintable as FakeAssetPaintable;
      void paint(AssetBinding binding) {
        final recorder = PictureRecorder();
        binding.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 8, 8));
        recorder.endRecording().dispose();
      }

      expect(still.paintable, same(paintable));
      paint(playing);
      paint(still);

      expect(
        [for (final paint in paintable.paints) paint.context.animate],
        [true, false],
      );
    });

    test('a small asset advances at 30 fps and a large one at 60', () {
      final small = animated(
        spec: _small,
        key: const ContentKey.document('small'),
      );
      final large = animated();
      var smallTicks = 0;
      var largeTicks = 0;
      small.addListener(() => smallTicks++);
      large.addListener(() => largeTicks++);

      for (var frame = 1; frame <= 12; frame++) {
        ticks.tick(Duration(microseconds: frame * 16667));
      }

      expect(largeTicks, 12);
      expect(smallTicks, 6);
    });
  });

  group('global pause layers', () {
    test('any layer stops playback and clearing it resumes', () {
      final binding = animated();

      scope.clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
      expect(binding.isPlaying, isFalse);
      expect(ticks.isRunning, isFalse);

      scope.clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
      expect(binding.isPlaying, isTrue);
      expect(ticks.isRunning, isTrue);
    });

    test('layers are independent: playback needs all of them clear', () {
      final binding = animated();
      scope.clock
        ..setPaused(PlaybackPauseLayer.fastScroll, paused: true)
        ..setPaused(PlaybackPauseLayer.lowPower, paused: true)
        ..setPaused(PlaybackPauseLayer.fastScroll, paused: false);

      expect(binding.isPlaying, isFalse);

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: false);
      expect(binding.isPlaying, isTrue);
    });

    test('a window that loses focus holds a binding and its first frame back '
        'carries that frame\'s time, a single step after ten seconds', () {
      final lifecycle = ManualPlaybackLifecycleSource(
        initial: AppLifecycleState.resumed,
      );
      addTearDown(lifecycle.dispose);
      final activity = PlaybackActivity(
        clock: scope.clock,
        lifecycle: lifecycle,
      );
      addTearDown(activity.dispose);
      final binding = animated();
      final paintable = binding.paintable as FakeAssetPaintable;
      var signals = 0;
      binding.addListener(() => signals++);
      ticks.tick(_ms(16));

      lifecycle.emit(AppLifecycleState.inactive);
      expect(binding.isPlaying, isFalse);
      expect(ticks.isRunning, isFalse);
      lifecycle.emit(AppLifecycleState.resumed);
      expect(binding.isPlaying, isTrue);
      ticks.tick(_ms(10016));
      final recorder = PictureRecorder();
      binding.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 8, 8));
      recorder.endRecording().dispose();

      expect(signals, 2, reason: 'one tick before the pause, one after');
      expect(paintable.paints.single.context.time, _ms(10016));
      expect(scope.isAttached(_key, _large), isTrue);
    });

    test('pausing does not detach or unpin anything', () {
      animated();

      scope.clock.setPaused(PlaybackPauseLayer.surfaceHidden, paused: true);

      expect(scope.isAttached(_key, _large), isTrue);
    });
  });

  group('one pass, a rest frame and a replay', () {
    final frames = [_ms(40), _ms(60), _ms(80)]; // a pass of 180 ms
    const once = AssetProfile(animate: true, loop: false);

    AssetBinding playing({AssetProfile profile = once, ContentKey key = _key}) {
      final binding = scope.attach(key, _large, profile);
      producer.last.advance(
        AssetStage.full,
        tier: AssetTier.animated,
        frames: frames,
      );
      return binding;
    }

    void paint(AssetBinding binding) {
      final recorder = PictureRecorder();
      binding.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 8, 8));
      recorder.endRecording().dispose();
    }

    // The engine's frame at [ms]: the clock ticks, the surface repaints.
    void frame(AssetBinding binding, int ms) {
      ticks.tick(_ms(ms));
      paint(binding);
    }

    // Plays a whole pass; the binding hears it has ended one frame later.
    void playPass(AssetBinding binding, {int from = 1000}) {
      frame(binding, from);
      frame(binding, from + 40);
      frame(binding, from + 100);
      frame(binding, from + 180);
      ticks.tick(_ms(from + 196));
    }

    test(
      'a binding that plays is playing, and idle while nothing animates',
      () {
        expect(playing().playback, AssetPlayback.playing);
        expect(
          animated(
            profile: const AssetProfile(),
            key: const ContentKey.document('b'),
          ).playback,
          AssetPlayback.idle,
        );
      },
    );

    test('the pass ends: the binding says so, signals once more and stops '
        'costing ticks', () {
      final binding = playing();
      var heard = 0;
      binding.addListener(() => heard++);
      frame(binding, 1000);
      frame(binding, 1040);
      frame(binding, 1100);
      expect(binding.playback, AssetPlayback.playing);

      frame(binding, 1180);
      expect(
        binding.playback,
        AssetPlayback.playing,
        reason: 'the paint held the frame; the next tick hears it',
      );
      heard = 0;
      ticks.tick(_ms(1196));

      expect(binding.playback, AssetPlayback.ended);
      expect(heard, greaterThan(0));
      expect(ticks.isRunning, isFalse);
      expect(binding.isPlaying, isFalse);
    });

    test('a profile that loops never ends', () {
      final binding = playing(profile: const AssetProfile(animate: true));

      playPass(binding);
      playPass(binding, from: 2000);

      expect(binding.playback, AssetPlayback.playing);
      expect(ticks.isRunning, isTrue);
    });

    test('it paints with the profile\'s loop and rest frame', () {
      final binding = playing(
        profile: const AssetProfile(
          animate: true,
          loop: false,
          restFrame: AssetRestFrame.last,
        ),
      );
      final paintable = binding.paintable as FakeAssetPaintable;

      frame(binding, 1000);

      final context = paintable.paints.single.context;
      expect(context.loop, isFalse);
      expect(context.restFrame, AssetRestFrame.last);
    });

    test('replay refuses while a pass runs, then plays another once it '
        'ended', () {
      final binding = playing();
      final paintable = binding.paintable as FakeAssetPaintable;
      frame(binding, 1000);
      frame(binding, 1040);

      expect(binding.replay(), isFalse);
      expect(paintable.restarts, 0);

      frame(binding, 1100);
      frame(binding, 1180);
      ticks.tick(_ms(1196));
      expect(binding.playback, AssetPlayback.ended);

      expect(binding.replay(), isTrue);
      expect(paintable.restarts, 1);
      expect(binding.playback, AssetPlayback.playing);
      expect(ticks.isRunning, isTrue);
      expect(binding.replay(), isFalse, reason: 'it is running again');

      // The new pass counts from its first paint and ends like the first.
      playPass(binding, from: 3000);
      expect(binding.playback, AssetPlayback.ended);
    });

    test('a replay signals the surface so it repaints', () {
      final binding = playing();
      playPass(binding);
      var heard = 0;
      binding.addListener(() => heard++);

      binding.replay();

      expect(heard, 1);
    });

    test('a profile that does not animate holds its first frame until a '
        'replay plays it', () {
      final binding = animated(
        profile: const AssetProfile(loop: false),
        key: const ContentKey.document('held'),
      );
      expect(binding.playback, AssetPlayback.idle);
      expect(ticks.isRunning, isFalse);

      expect(binding.replay(), isTrue);

      expect(binding.playback, AssetPlayback.playing);
      expect(ticks.isRunning, isTrue);
      expect(binding.replay(), isFalse);
    });

    test('a replay paints at the clock again, not at the time it held', () {
      final binding = animated(
        profile: const AssetProfile(loop: false),
        key: const ContentKey.document('held'),
      );
      final paintable = binding.paintable as FakeAssetPaintable;
      paint(binding);
      expect(paintable.paints.single.context.animate, isFalse);

      binding.replay();
      ticks.tick(_ms(500));
      paint(binding);

      expect(paintable.paints.last.context.animate, isTrue);
      expect(paintable.paints.last.context.time, _ms(500));
    });

    test('replay refuses a binding that is hidden, detached, still or '
        'short of the animated stage', () {
      final hidden = playing()..visible = false;
      expect(hidden.replay(), isFalse);

      final still = scope.attach(
        const ContentKey.document('still'),
        _large,
        const AssetProfile(loop: false),
      );
      producer.last.advance(AssetStage.full);
      expect(still.replay(), isFalse);

      final early = scope.attach(
        const ContentKey.document('early'),
        _large,
        const AssetProfile(loop: false),
      );
      producer.last.advance(AssetStage.placeholder);
      expect(early.replay(), isFalse);

      final gone = playing(key: const ContentKey.document('gone'))..detach();
      expect(gone.replay(), isFalse);
    });

    test('a paused clock holds the pass where it is, and the pass ends '
        'after it resumes', () {
      final binding = playing();
      frame(binding, 1000);
      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);
      expect(ticks.isRunning, isFalse);
      expect(binding.playback, AssetPlayback.playing);

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: false);
      frame(binding, 1040);
      frame(binding, 1100);
      frame(binding, 1180);
      ticks.tick(_ms(1196));

      expect(binding.playback, AssetPlayback.ended);
    });

    test('a binding that starts playing wakes a playback another binding '
        'left holding', () {
      final first = playing();
      playPass(first);
      expect(first.playback, AssetPlayback.ended);
      final paintable = first.paintable as FakeAssetPaintable;

      final second = scope.attach(_key, _large, once);

      expect(second.playback, AssetPlayback.playing);
      expect(paintable.restarts, 1);
    });
  });
}
