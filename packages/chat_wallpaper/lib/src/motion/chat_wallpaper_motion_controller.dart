/// @docImport 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_scope.dart';
library;

import 'dart:math' as math;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:chat_wallpaper/src/render/freeform_gradient.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Moves a freeform wallpaper's colour points around their ring, and owns the
/// keyframes every view under it paints.
///
/// ## Timeline
///
/// [phase] and [progress] are the [FreeformGradient] inputs: the colour points
/// sit [progress] of the way from their slots at `phase + 1` to their slots at
/// [phase]. At rest [progress] is `1`; a new controller rests at phase `0`.
///
/// - [advance] runs one step, to `phase − 1` (wrapping from `0` to `7`), over
///   [shiftDuration].
/// - [swirl] runs [swirlSteps] consecutive steps over [swirlDuration]: an
///   entrance motion, longer than a shift, for when a wallpaper first shows.
/// - [holdSpin] turns the ring the other way for as long as it is held; see
///   the loading spin below.
///
/// [curve] eases the whole of an [advance] or [swirl] run. A multi-step run
/// splits the eased value into equal parts, one per step, with [progress]
/// rising linearly within each. [phase] therefore changes when a step begins,
/// with [progress] at `0`: that frame is identical to the settled frame of
/// the phase just left.
///
/// A request while [isAnimating] is ignored rather than queued, so a burst of
/// requests never stretches the motion beyond one run. Both requests report
/// whether their run started, so callers can tie feedback to the real outcome.
///
/// ## Loading spin
///
/// The spin is continuous motion for as long as something waits: it runs
/// while at least one [ChatWallpaperSpinHold] from [holdSpin] is held. It
/// turns towards `phase + 1`, the reverse of [advance], at one step per
/// [spinStepDuration], linearly and without pausing at step boundaries:
/// [progress] falls from `1` to `0` at [phase], which then rises by one with
/// [progress] back at `1`.
///
/// Releasing the last hold ends the spin by easing back, linearly, to the
/// arrangement the current step started from — [phase] settled — at
/// [spinReturnDuration] per full step, so a spin released a quarter of the
/// way into a step returns in a quarter of that. The controller rests at that
/// phase. A hold taken during the return resumes the spin from where the
/// colour points are.
///
/// Holds taken while an [advance] or [swirl] run is in progress start the
/// spin once that run settles. Requests for [advance] and [swirl] are ignored
/// while the spin runs or returns.
///
/// ## Reduced motion
///
/// While [disableAnimations] is set, [advance], [swirl] and the spin do
/// nothing: the phase stays where it is and no listener is notified. Setting
/// it during a run ends the run immediately, settled at its target — for the
/// spin, the current step's start. Clearing it while a hold is open starts
/// the spin.
/// [ChatWallpaperMotionScope] and [ChatWallpaperMotionStateMixin] keep the
/// flag in step with the platform setting.
///
/// ## Keyframes
///
/// A `ChatWallpaperView` given this controller paints a freeform fill from
/// keyframes the controller holds per wallpaper value. Every copy of one
/// wallpaper under the same controller — a background and a masked copy over
/// it, say — therefore paints the same images in the same frame and can never
/// drift apart.
///
/// A run paints its settled starting frame, then three keyframes per step
/// (progress `⅓`, `⅔`, `1`); frames in between crossfade neighbouring
/// keyframes rather than rasterizing again. The keyframes are the
/// arrangements of the wallpaper's ring: 24 of them, 8 phases × 3 thirds.
///
/// While a value is held, its whole ring is kept and warmed in the
/// background, one keyframe at a time, nearest the phase it rests at first.
/// Once the ring is warm, a shift, a swirl and the spin all start on
/// keyframes already held, so no run rasterizes when it starts and none
/// is thrown away when it settles. A run started before the ring is warm
/// has its missing keyframes warmed first, in the order it plays them; it
/// never waits for them and paints the nearest landed keyframe meanwhile.
/// Each held value costs up to 24 textures of 60 × 80 pixels, about 460 KB.
/// While [disableAnimations] is set, no run can play: a held value keeps
/// only the keyframe it rests on and warms nothing, until motion is
/// enabled again.
///
/// Holders are the views painting a value and any warm-up host keeping it
/// ready; its keyframes are released when the last holder lets go, and a
/// keyframe landing after that is disposed on arrival. A held value warms
/// and follows every run whether or not a view paints it, so a view that
/// mounts later, even mid-run, paints keyframes that have already landed.
///
/// Solid and linear fills have no colour points and ignore the controller.
///
/// ## Lifecycle
///
/// Ticks through [vsync], normally the owning `State`: a
/// [ChatWallpaperMotionScope] shared by a subtree, or one host through
/// [ChatWallpaperMotionStateMixin]. Notifies listeners on every tick of a run
/// and on each settled jump. Dispose it with its owner, after the views using
/// it; releasing keyframes or a spin hold after [dispose] is a no-op.
class ChatWallpaperMotionController extends ChangeNotifier {
  /// Creates a controller resting at phase `0` with animations enabled.
  ChatWallpaperMotionController({required TickerProvider vsync})
    : _timeline = AnimationController.unbounded(vsync: vsync) {
    _timeline
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  /// Length of the one-step shift run by [advance].
  static const Duration shiftDuration = Duration(milliseconds: 500);

  /// Length of the [swirlSteps]-step run started by [swirl].
  static const Duration swirlDuration = Duration(seconds: 2);

  /// Number of phase steps one [swirl] moves.
  static const int swirlSteps = 4;

  /// Easing applied across a whole [advance] or [swirl] run.
  static const Cubic curve = Cubic(0.33, 0, 0, 1);

  /// Time the held spin takes per phase step.
  static const Duration spinStepDuration = Duration(seconds: 1);

  /// Time the spin's return takes for a full step; a partial step returns in
  /// proportion.
  static const Duration spinReturnDuration = Duration(milliseconds: 500);

  /// Raw run time, mapped to [phase] and [progress] by [_run]: `0` … `1` for
  /// an [advance] or [swirl] run; for the spin, steps into the current lap of
  /// the ring (`0` … `phaseCount`, wrapping).
  final AnimationController _timeline;

  final Map<ChatWallpaper$Freeform, _KeyframesLease> _leases = {};

  int _phase = 0;
  double _progress = 1;

  /// The run in progress; `null` between runs.
  _Run? _run;

  /// Number of [ChatWallpaperSpinHold]s not yet released.
  int _spinHolds = 0;

  bool _disableAnimations = false;

  /// Ring phase the colour points are moving to, or rest at (`0` … `7`).
  int get phase => _phase;

  /// Progress (`0` … `1`) of the current step towards [phase]; `1` at rest.
  double get progress => _progress;

  /// Whether a run, the spin, or its return is in progress; [advance] and
  /// [swirl] are ignored meanwhile.
  bool get isAnimating => _timeline.isAnimating;

  /// Whether motion is suppressed, normally mirrored from the platform's
  /// reduced-motion setting.
  bool get disableAnimations => _disableAnimations;

  set disableAnimations(bool value) {
    if (value == _disableAnimations) return;
    _disableAnimations = value;
    if (_run case final run? when value) {
      _timeline.stop();
      _moveTo(run.restingPhase(_timeline.value), 1);
      _settle();
    }
    for (final lease in _leases.values) {
      lease.keyframes.warmsRing = !value;
    }
    if (!value && _spinHolds > 0) _spin();
  }

  /// Starts a one-step shift to `phase − 1` over [shiftDuration] and returns
  /// `true`; returns `false` without moving while [isAnimating] or
  /// [disableAnimations].
  bool advance() => _start(steps: 1, duration: shiftDuration);

  /// Starts a [swirlSteps]-step run to `phase − swirlSteps` over
  /// [swirlDuration] and returns `true`; returns `false` without moving while
  /// [isAnimating] or [disableAnimations].
  ///
  /// The run blocks [advance] and [swirl] until it settles.
  bool swirl() => _start(steps: swirlSteps, duration: swirlDuration);

  /// Holds the loading spin until the returned hold is released.
  ///
  /// The spin starts now when the controller is at rest, or once the run in
  /// progress settles; a hold taken during the spin's return resumes it.
  /// While [disableAnimations] is set the hold is counted but moves nothing.
  /// Every hold must be released, including by a holder that leaves before
  /// its wait is over; the spin ends when the last one is.
  ChatWallpaperSpinHold holdSpin() {
    assert(
      ChangeNotifier.debugAssertNotDisposed(this),
      'holdSpin() called after dispose()',
    );
    if (++_spinHolds == 1) _spin();
    return ChatWallpaperSpinHold._(this);
  }

  /// Keyframes of [wallpaper] for the run in progress, or for the settled
  /// [phase] between runs, shared with every other holder of the same value.
  /// The first hold starts warming the value's ring unless
  /// [disableAnimations] is set. Pair each call with [releaseKeyframes].
  @internal
  FreeformKeyframes acquireKeyframes(ChatWallpaper$Freeform wallpaper) {
    assert(
      ChangeNotifier.debugAssertNotDisposed(this),
      'acquireKeyframes() called after dispose()',
    );
    final (from, steps) = switch (_run) {
      final run? => (run.origin, run.stripSteps),
      null => (_phase, 0),
    };
    final lease = _leases[wallpaper] ??= _KeyframesLease(
      FreeformKeyframes(
        wallpaper,
        from: from,
        steps: steps,
        warmsRing: !_disableAnimations,
      ),
    );
    lease.holders++;
    return lease.keyframes;
  }

  /// Drops one hold on [wallpaper]'s keyframes; the last release disposes
  /// every keyframe of its ring and stops warming it.
  @internal
  void releaseKeyframes(ChatWallpaper$Freeform wallpaper) {
    final lease = _leases[wallpaper];
    if (lease == null || --lease.holders > 0) return;
    _leases.remove(wallpaper);
    lease.keyframes.dispose();
  }

  /// Starts a [steps]-step run over [duration]; `false`, without side effects,
  /// while [isAnimating] or [disableAnimations].
  bool _start({required int steps, required Duration duration}) {
    if (isAnimating || _disableAnimations) return false;
    _begin(_StepRun(origin: _phase, steps: steps));
    _timeline.animateTo(1, duration: duration);
    return true;
  }

  /// Starts or resumes the spin for the open holds, unless another run owns
  /// the timeline — [_onStatus] spins once it settles — or motion is off.
  void _spin() {
    if (_disableAnimations) return;
    switch (_run) {
      case _StepRun():
        return;
      case _SpinRun():
        _repeatLaps();
      case null:
        _begin(_SpinRun(origin: _phase));
        _repeatLaps();
    }
  }

  /// Runs the spin's timeline linearly from its current value, one lap of the
  /// ring per `phaseCount` steps, without end.
  void _repeatLaps() => _timeline.repeat(
    min: 0,
    max: FreeformGradient.phaseCount.toDouble(),
    period: spinStepDuration * FreeformGradient.phaseCount,
  );

  /// Ends the spin with its linear return to the current step's start.
  void _releaseSpin() {
    if (_spinHolds == 0 || --_spinHolds > 0) return;
    if (_run case _SpinRun()) {
      final turned = _timeline.value;
      final stepStart = turned.floorToDouble();
      // A zero duration completes synchronously, settling through [_onStatus].
      _timeline.animateTo(
        stepStart,
        duration: spinReturnDuration * (turned - stepStart),
      );
    }
  }

  /// Makes [run] current: moves its missing keyframes to the front of each
  /// value's warming and rewinds the timeline to its start. The rewind
  /// notifies [_onTick] synchronously, so the run's first frame is in place
  /// before any caller reads [phase].
  void _begin(_Run run) {
    _run = run;
    for (final lease in _leases.values) {
      lease.keyframes.run(from: run.origin, steps: run.stripSteps);
    }
    _timeline.value = 0;
  }

  void _onTick() {
    if (_run case final run?) {
      final (:phase, :progress) = run.at(_timeline.value);
      _moveTo(phase, progress);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (!status.isCompleted) return;
    _settle();
    if (_spinHolds > 0) _spin();
  }

  /// Ends the run at the current [phase]: keyframes rest on that phase's
  /// settled frame and warm the ring outward from it.
  void _settle() {
    _run = null;
    for (final lease in _leases.values) {
      lease.keyframes.settle(phase: _phase);
    }
  }

  void _moveTo(int phase, double progress) {
    if (phase == _phase && progress == _progress) return;
    _phase = phase;
    _progress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    _run = null;
    _spinHolds = 0;
    _timeline.dispose();
    for (final lease in _leases.values) {
      lease.keyframes.dispose();
    }
    _leases.clear();
    super.dispose();
  }
}

/// One claim on a [ChatWallpaperMotionController]'s loading spin, returned by
/// [ChatWallpaperMotionController.holdSpin].
///
/// The spin runs while any claim is open. Release it when the wait it stands
/// for is over, and from the holder's teardown if that comes first.
final class ChatWallpaperSpinHold {
  ChatWallpaperSpinHold._(this._motion);

  ChatWallpaperMotionController? _motion;

  /// Gives up this claim; the last open claim ends the spin. Later calls, and
  /// calls after the controller is disposed, do nothing.
  void release() {
    final motion = _motion;
    if (motion == null) return;
    _motion = null;
    motion._releaseSpin();
  }
}

/// Gives a [State] a [ChatWallpaperMotionController] for its lifetime.
///
/// Creates [wallpaperMotion] in [initState], keeps
/// [ChatWallpaperMotionController.disableAnimations] equal to
/// [MediaQuery.disableAnimationsOf] from [didChangeDependencies] on, and
/// disposes the controller in [dispose]. The controller ticks through this
/// state, so mix this in after a ticker provider mixin, e.g.
/// `with SingleTickerProviderStateMixin, ChatWallpaperMotionStateMixin`.
///
/// The timeline is private to this state: it starts at phase `0` with every
/// mount and moves only this state's views. Hosts that share one phase read a
/// [ChatWallpaperMotionScope] instead.
mixin ChatWallpaperMotionStateMixin<T extends StatefulWidget>
    on State<T>, TickerProvider {
  /// Motion source for every wallpaper view this state builds.
  late final ChatWallpaperMotionController wallpaperMotion;

  @override
  void initState() {
    super.initState();
    wallpaperMotion = ChatWallpaperMotionController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    wallpaperMotion.disableAnimations = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    wallpaperMotion.dispose();
    super.dispose();
  }
}

/// A run on the controller's timeline: which keyframe strip it paints and how
/// timeline values map to phase and progress.
sealed class _Run {
  const _Run({required this.origin});

  /// Phase the run starts from: the first frame of its keyframe strip.
  final int origin;

  /// Steps of the keyframe strip the run paints, from [origin].
  int get stripSteps;

  /// Phase and progress at timeline value [t].
  ({int phase, double progress}) at(double t);

  /// Phase to rest at when the run is cut short at timeline value [t].
  int restingPhase(double t);

  static int _phaseAfter(int steps, {required int from}) =>
      (from - steps) % FreeformGradient.phaseCount;
}

/// An [ChatWallpaperMotionController.advance] or
/// [ChatWallpaperMotionController.swirl] run: [steps] steps towards
/// `phase − 1`, eased as a whole over a `0` … `1` timeline.
final class _StepRun extends _Run {
  const _StepRun({required super.origin, required this.steps});

  final int steps;

  @override
  int get stripSteps => steps;

  @override
  ({int phase, double progress}) at(double t) {
    final eased = ChatWallpaperMotionController.curve.transform(t) * steps;
    final step = math.min(eased.floor(), steps - 1);
    return (
      phase: _Run._phaseAfter(step + 1, from: origin),
      progress: eased - step,
    );
  }

  @override
  int restingPhase(double t) => _Run._phaseAfter(steps, from: origin);
}

/// The held spin towards `phase + 1`; the timeline counts steps into the
/// current lap, so its whole part is the step and its fraction how far into
/// it. A lap ends back at [origin], so the wrap to `0` is seamless.
final class _SpinRun extends _Run {
  const _SpinRun({required super.origin});

  @override
  int get stripSteps => FreeformGradient.phaseCount;

  @override
  ({int phase, double progress}) at(double t) =>
      (phase: restingPhase(t), progress: 1 - (t - t.floor()));

  @override
  int restingPhase(double t) => _Run._phaseAfter(-t.floor(), from: origin);
}

/// One wallpaper's shared keyframes and how many views hold them.
class _KeyframesLease {
  _KeyframesLease(this.keyframes);

  final FreeformKeyframes keyframes;
  int holders = 0;
}
