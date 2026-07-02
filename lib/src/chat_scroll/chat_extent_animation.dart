import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Telegram-style cubic — for one-shot opacity (and optional horizontal width).
/// Not used for vertical height: [Cubic] cannot retarget with velocity continuity.
const Curve telegramCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

/// Default critically damped spring for vertical message extent (no overshoot).
final SpringDescription kDefaultHeightSpring =
    SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1);

/// Fixed-duration eased scalar run (opacity, optional horizontal width).
class CurveRun {
  /// Starts a run from [from] to [to] over [duration] using [curve].
  CurveRun(this.curve, this.duration, this.from, this.to);

  /// Easing curve (typically [telegramCurve]).
  final Curve curve;

  /// Total animation duration.
  final Duration duration;

  /// Start value.
  final double from;

  /// End value.
  final double to;

  /// Elapsed time in milliseconds since the run started.
  double elapsedMs = 0;

  /// Current interpolated value in `[from, to]`.
  double get value {
    if (duration.inMilliseconds <= 0) return to;
    final t = (elapsedMs / duration.inMilliseconds).clamp(0.0, 1.0);
    return from + (to - from) * curve.transform(t);
  }

  /// Advances by [dtMs] milliseconds. Returns `true` when the run has finished.
  bool advance(double dtMs) {
    if (dtMs <= 0) return elapsedMs >= duration.inMilliseconds;
    elapsedMs += dtMs;
    return elapsedMs >= duration.inMilliseconds;
  }
}

/// Retarget-safe vertical extent driven by [SpringSimulation].
///
/// Advanced by [advance] each viewport tick using frame delta — not tied to
/// absolute [Ticker] elapsed time, so restarts do not rewind the simulation.
class ExtentSpring {
  /// Starts a new spring from [from] toward [to] with initial [velocity].
  factory ExtentSpring.start({
    required double from,
    required double to,
    required double velocity,
    SpringDescription? spring,
  }) {
    final description = spring ?? kDefaultHeightSpring;
    final sim = SpringSimulation(
      description,
      from,
      to,
      velocity,
      snapToEnd: true,
    );
    return ExtentSpring._(sim);
  }

  ExtentSpring._(this._sim);

  SpringSimulation _sim;
  double _t = 0;

  /// Elapsed simulation time in seconds since start / last [retarget].
  double get elapsedSeconds => _t;

  /// Current extent value.
  double get value => _sim.x(_t);

  /// Current velocity.
  double get velocity => _sim.dx(_t);

  /// Whether the spring has settled.
  bool get isDone => _sim.isDone(_t);

  /// Advances the simulation by [dtSeconds].
  void advance(double dtSeconds) {
    if (dtSeconds <= 0) return;
    _t += dtSeconds;
  }

  /// Re-targets toward [newTarget] preserving current value and velocity.
  void retarget(double newTarget, {SpringDescription? spring}) {
    final description = spring ?? kDefaultHeightSpring;
    final currentValue = _sim.x(_t);
    final currentVelocity = _sim.dx(_t);
    _sim = SpringSimulation(
      description,
      currentValue,
      newTarget,
      currentVelocity,
      snapToEnd: true,
    );
    _t = 0;
  }
}

/// Optional horizontal bubble width animation — dispatched from viewport tick.
abstract class HasHorizontalExtentAnimation {
  /// Target laid-out bubble width.
  double get targetBubbleWidth;

  /// Current animated width used for paint.
  double get animatedBubbleWidth;

  /// Whether a horizontal animation is still running.
  bool get horizontalAnimationActive;

  /// Advance horizontal animation by [dtMs] milliseconds.
  void advanceHorizontal(double dtMs);

  /// Start or retarget toward [newTargetWidth].
  void retargetHorizontal(double newTargetWidth);
}
