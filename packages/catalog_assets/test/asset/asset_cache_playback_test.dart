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

      expect([for (final paint in paintable.paints) paint.context.animate], [
        true,
        false,
      ]);
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

    test('pausing does not detach or unpin anything', () {
      animated();

      scope.clock.setPaused(PlaybackPauseLayer.surfaceHidden, paused: true);

      expect(scope.isAttached(_key, _large), isTrue);
    });
  });
}
