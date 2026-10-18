import 'dart:ui' show AppLifecycleState;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _ms(int ms) => Duration(milliseconds: ms);

final class _Target implements PlaybackTarget {
  @override
  Duration get frameInterval => _ms(16);

  final List<Duration> ticks = [];

  @override
  void tick(Duration now) => ticks.add(now);
}

void main() {
  late ManualPlaybackTickSource frames;
  late PlaybackClock clock;
  late ManualPlaybackLifecycleSource lifecycle;
  late ManualRetentionTimers timers;
  final created = <PlaybackActivity>[];

  setUp(() {
    frames = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: frames);
    lifecycle = ManualPlaybackLifecycleSource();
    timers = ManualRetentionTimers();
  });
  tearDown(() {
    created
      ..forEach((activity) => activity.dispose())
      ..clear();
    lifecycle.dispose();
    clock.dispose();
  });

  PlaybackActivity activity({
    PlaybackLifecycleSource? source,
    ValueListenable<bool>? lowPower,
    ValueListenable<bool>? reducedMotion,
    PlaybackActivityPolicy policy = const PlaybackActivityPolicy(),
    bool withLifecycle = true,
  }) {
    final made = PlaybackActivity(
      clock: clock,
      lifecycle: withLifecycle ? (source ?? lifecycle) : null,
      lowPower: lowPower,
      reducedMotion: reducedMotion,
      policy: policy,
      startTimer: timers.start,
    );
    created.add(made);
    return made;
  }

  group('the lifecycle becomes two layers', () {
    // state -> (appInactive, surfaceHidden), with no grace.
    const table = <AppLifecycleState, (bool, bool)>{
      AppLifecycleState.resumed: (false, false),
      AppLifecycleState.inactive: (true, false),
      AppLifecycleState.hidden: (true, true),
      AppLifecycleState.paused: (true, true),
    };

    for (final MapEntry(key: state, value: (inactive, hidden))
        in table.entries) {
      test('$state: appInactive $inactive, surfaceHidden $hidden', () {
        activity();

        // Reached from another state, so the change is a real one.
        lifecycle.emit(
          state == AppLifecycleState.resumed
              ? AppLifecycleState.hidden
              : AppLifecycleState.resumed,
        );
        lifecycle.emit(state);

        expect(
          clock.pausedLayers.contains(PlaybackPauseLayer.appInactive),
          inactive,
        );
        expect(
          clock.pausedLayers.contains(PlaybackPauseLayer.surfaceHidden),
          hidden,
        );
      });
    }

    test('nothing is set while the platform has not said anything', () {
      activity();

      expect(clock.pausedLayers, isEmpty);
    });

    test('a first state of detached is not yet a reason to pause', () {
      lifecycle.dispose();
      lifecycle = ManualPlaybackLifecycleSource(
        initial: AppLifecycleState.detached,
      );

      activity();

      expect(clock.pausedLayers, isEmpty);
    });

    test('detached after a real state hides the surface', () {
      activity();
      lifecycle
        ..emit(AppLifecycleState.resumed)
        ..emit(AppLifecycleState.detached);

      expect(clock.pausedLayers, {
        PlaybackPauseLayer.appInactive,
        PlaybackPauseLayer.surfaceHidden,
      });
    });

    test('a state the source already has when the activity starts counts', () {
      lifecycle.dispose();
      lifecycle = ManualPlaybackLifecycleSource(
        initial: AppLifecycleState.inactive,
      );

      activity();

      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});
    });

    test('resumed to hidden arrives as inactive then hidden and stops the '
        'frames once', () {
      activity();
      clock.register(_Target());
      lifecycle.emit(AppLifecycleState.resumed);
      expect(frames.isRunning, isTrue);

      lifecycle.emitAll([AppLifecycleState.inactive, AppLifecycleState.hidden]);

      expect(clock.pausedLayers, {
        PlaybackPauseLayer.appInactive,
        PlaybackPauseLayer.surfaceHidden,
      });
      expect(frames.isRunning, isFalse);
      expect(frames.stops, 1);
    });

    test('hidden to resumed clears both and the frames come back', () {
      activity();
      clock.register(_Target());
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]);

      lifecycle.emitAll([
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);

      expect(clock.pausedLayers, isEmpty);
      expect(frames.isRunning, isTrue);
    });

    test('showing a hidden window that has no focus keeps appInactive', () {
      activity();
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]);

      lifecycle.emit(AppLifecycleState.inactive);

      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});
    });

    test('a policy without appInactive lets focus loss through', () {
      final custom = PlaybackClock(
        ticks: ManualPlaybackTickSource(),
        policy: const PlaybackPolicy(
          pausingLayers: {PlaybackPauseLayer.surfaceHidden},
        ),
      );
      addTearDown(custom.dispose);
      final made = PlaybackActivity(clock: custom, lifecycle: lifecycle);
      addTearDown(made.dispose);

      lifecycle.emit(AppLifecycleState.inactive);
      expect(custom.isPaused, isFalse);

      lifecycle.emit(AppLifecycleState.hidden);
      expect(custom.isPaused, isTrue);
    });

    test('a layer the host raised is not cleared by a state that is merely '
        'not hidden', () {
      activity();
      clock.setPaused(PlaybackPauseLayer.surfaceHidden, paused: true);

      lifecycle
        ..emit(AppLifecycleState.resumed)
        ..emit(AppLifecycleState.inactive);

      expect(clock.pausedLayers, contains(PlaybackPauseLayer.surfaceHidden));
    });

    test('layers the host sets itself are neither set nor cleared by it', () {
      activity();
      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);

      lifecycle
        ..emit(AppLifecycleState.inactive)
        ..emit(AppLifecycleState.resumed);

      expect(clock.pausedLayers, {PlaybackPauseLayer.fastScroll});
    });
  });

  group('the grace periods', () {
    const grace = PlaybackActivityPolicy(
      unfocusedGrace: Duration(seconds: 1),
      focusedGrace: Duration(seconds: 5),
    );

    test('are zero by default: focus loss pauses in the same turn', () {
      activity();

      lifecycle.emit(AppLifecycleState.inactive);

      expect(timers.pending, 0);
      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});
    });

    test('focus loss pauses once the grace has passed', () {
      activity(policy: grace);
      lifecycle.emit(AppLifecycleState.resumed);

      lifecycle.emit(AppLifecycleState.inactive);
      timers.elapse(_ms(999));
      expect(clock.pausedLayers, isEmpty);

      timers.elapse(_ms(1));
      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});
    });

    test('losing visibility while the grace runs does not wait for it', () {
      activity(policy: grace);
      lifecycle.emit(AppLifecycleState.resumed);

      lifecycle.emit(AppLifecycleState.inactive);
      lifecycle.emit(AppLifecycleState.hidden);

      expect(clock.pausedLayers, {
        PlaybackPauseLayer.appInactive,
        PlaybackPauseLayer.surfaceHidden,
      });
      expect(timers.pending, 0);
    });

    test('focus back within the grace never pauses', () {
      activity(policy: grace);
      lifecycle.emit(AppLifecycleState.resumed);

      lifecycle.emit(AppLifecycleState.inactive);
      timers.elapse(_ms(500));
      lifecycle.emit(AppLifecycleState.resumed);
      timers.elapse(const Duration(seconds: 10));

      expect(clock.pausedLayers, isEmpty);
      expect(timers.pending, 0);
    });

    test('focus back resumes once its grace has passed', () {
      activity(policy: grace);
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      timers.elapse(const Duration(seconds: 1));
      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});

      lifecycle.emit(AppLifecycleState.resumed);
      timers.elapse(_ms(4999));
      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});

      timers.elapse(_ms(1));
      expect(clock.pausedLayers, isEmpty);
    });

    test('focus lost again within the resume grace stays paused', () {
      activity(policy: grace);
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      timers.elapse(const Duration(seconds: 1));

      lifecycle.emit(AppLifecycleState.resumed);
      timers.elapse(const Duration(seconds: 2));
      lifecycle.emit(AppLifecycleState.inactive);
      timers.elapse(const Duration(seconds: 10));

      expect(clock.pausedLayers, {PlaybackPauseLayer.appInactive});
      expect(timers.pending, 0);
    });

    test('hiding is immediate whatever the grace, and cancels a pending '
        'resume', () {
      activity(policy: grace);
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      timers.elapse(const Duration(seconds: 1));
      lifecycle.emit(AppLifecycleState.resumed);

      lifecycle.emitAll([AppLifecycleState.inactive, AppLifecycleState.hidden]);
      timers.elapse(const Duration(seconds: 10));

      expect(clock.pausedLayers, {
        PlaybackPauseLayer.appInactive,
        PlaybackPauseLayer.surfaceHidden,
      });
    });
  });

  group('low power and reduced motion', () {
    test('lowPower forwards in both directions, starting from its value', () {
      final lowPower = ValueNotifier<bool>(true);
      addTearDown(lowPower.dispose);
      activity(lowPower: lowPower);
      expect(clock.pausedLayers, {PlaybackPauseLayer.lowPower});

      lowPower.value = false;
      expect(clock.pausedLayers, isEmpty);

      lowPower.value = true;
      expect(clock.pausedLayers, {PlaybackPauseLayer.lowPower});
    });

    test('reducedMotion forwards both ways but does not pause by default', () {
      final reduced = ValueNotifier<bool>(false);
      addTearDown(reduced.dispose);
      activity(reducedMotion: reduced);
      clock.register(_Target());

      reduced.value = true;

      expect(clock.pausedLayers, {PlaybackPauseLayer.reducedMotion});
      expect(clock.isPaused, isFalse);
      expect(frames.isRunning, isTrue);

      reduced.value = false;
      expect(clock.pausedLayers, isEmpty);
    });

    test('work without a lifecycle source', () {
      final lowPower = ValueNotifier<bool>(false);
      addTearDown(lowPower.dispose);
      activity(withLifecycle: false, lowPower: lowPower);

      lowPower.value = true;

      expect(clock.pausedLayers, {PlaybackPauseLayer.lowPower});
    });

    test('are independent of the lifecycle layers', () {
      final lowPower = ValueNotifier<bool>(true);
      addTearDown(lowPower.dispose);
      activity(lowPower: lowPower);

      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      lifecycle.emit(AppLifecycleState.resumed);

      expect(clock.pausedLayers, {PlaybackPauseLayer.lowPower});
    });
  });

  group('overlays over the chat', () {
    test('a hold sets overlayShown and releasing it clears it', () {
      final made = activity();
      clock.register(_Target());

      final hold = made.holdOverlay();
      expect(clock.pausedLayers, {PlaybackPauseLayer.overlayShown});
      expect(frames.isRunning, isFalse);

      hold.release();
      expect(clock.pausedLayers, isEmpty);
      expect(frames.isRunning, isTrue);
    });

    test('nested overlays keep it set until the last is released', () {
      final made = activity();
      final dialog = made.holdOverlay();
      final sheet = made.holdOverlay();

      dialog.release();
      expect(clock.pausedLayers, {PlaybackPauseLayer.overlayShown});

      sheet.release();
      expect(clock.pausedLayers, isEmpty);
    });

    test('releasing a hold twice releases it once', () {
      final made = activity();
      final first = made.holdOverlay();
      made.holdOverlay();

      first
        ..release()
        ..release();

      expect(clock.pausedLayers, {PlaybackPauseLayer.overlayShown});
      expect(first.isReleased, isTrue);
    });

    test('are independent of focus and visibility', () {
      final made = activity();
      final hold = made.holdOverlay();

      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      lifecycle.emit(AppLifecycleState.resumed);

      expect(clock.pausedLayers, {PlaybackPauseLayer.overlayShown});
      hold.release();
    });

    test('a hold taken after dispose is already released and changes '
        'nothing', () {
      final made = activity()..dispose();

      final hold = made.holdOverlay();

      expect(hold.isReleased, isTrue);
      expect(clock.pausedLayers, isEmpty);
    });
  });

  group('dispose', () {
    test('clears every layer it set and keeps the host\'s own', () {
      final lowPower = ValueNotifier<bool>(true);
      addTearDown(lowPower.dispose);
      final made = activity(lowPower: lowPower);
      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]);
      made.holdOverlay();

      made.dispose();

      expect(clock.pausedLayers, {PlaybackPauseLayer.fastScroll});
    });

    test('stops listening: later reports and holds change nothing', () {
      final lowPower = ValueNotifier<bool>(false);
      addTearDown(lowPower.dispose);
      final made = activity(lowPower: lowPower)..dispose();

      lifecycle.emit(AppLifecycleState.hidden);
      lowPower.value = true;
      final hold = made.holdOverlay();
      hold.release();

      expect(clock.pausedLayers, isEmpty);
      expect(lifecycle.isListened, isFalse);
    });

    test('drops a pending grace timer', () {
      final made = activity(
        policy: const PlaybackActivityPolicy(
          unfocusedGrace: Duration(seconds: 1),
        ),
      );
      lifecycle.emitAll([
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      expect(timers.pending, 1);

      made.dispose();
      timers.elapse(const Duration(seconds: 5));

      expect(timers.pending, 0);
      expect(clock.pausedLayers, isEmpty);
    });

    test('is idempotent', () {
      final made = activity();

      made
        ..dispose()
        ..dispose();

      expect(made.isDisposed, isTrue);
    });

    test('does not dispose what it was given', () {
      final lowPower = ValueNotifier<bool>(false);
      addTearDown(lowPower.dispose);
      activity(lowPower: lowPower).dispose();

      // A disposed notifier would throw here.
      lowPower.value = true;
      lifecycle.emit(AppLifecycleState.inactive);
    });
  });

  group('what the pause does to the animations', () {
    test('losing focus for ten seconds costs one tick on the first frame '
        'back, stamped with that frame', () {
      activity();
      final target = _Target();
      clock.register(target);
      lifecycle.emit(AppLifecycleState.resumed);
      frames.tick(_ms(16));

      lifecycle.emit(AppLifecycleState.inactive);
      expect(frames.isRunning, isFalse);
      lifecycle.emit(AppLifecycleState.resumed);
      frames.tick(_ms(10016));

      expect(target.ticks, [_ms(16), _ms(10016)]);
      expect(clock.now, _ms(10016));
    });

    test('a follower of the clock (the spoiler dust) stands still while the '
        'window has no focus and moves again after', () {
      activity();
      final seen = <Duration>[];
      clock.follow(seen.add, frameInterval: _ms(33));
      lifecycle.emit(AppLifecycleState.resumed);
      frames.tick(_ms(40));

      lifecycle.emit(AppLifecycleState.inactive);
      frames.tick(_ms(80));
      lifecycle.emit(AppLifecycleState.resumed);
      frames.tick(_ms(120));

      expect(seen, [_ms(40), _ms(120)]);
    });
  });
}
