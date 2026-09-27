import 'dart:math' as math;

import 'package:flutter/physics.dart' show Simulation;

/// Inertial fling for the chat viewport.
///
/// Owns [ChatSplineFlingSimulation] start / tick / cancel. Does **not** own
/// boundary stretch — that lives on [ChatStretchOverscroll] (paint-only).
///
/// **Host wiring**: call [startFling] from drag-end when stretch is inactive
/// and content has travel range; [tickFling] from the viewport ticker;
/// [cancelFling] on drag-start, jump, or when a pin wall is hit.
class ChatScrollPhysics {
  /// Creates fling physics.
  ChatScrollPhysics();

  ChatSplineFlingSimulation? _simulation;

  /// Ticker `elapsed` at the first tick of the current fling, or `null`
  /// between flings. Nullable on purpose — a [Ticker]'s very first `elapsed`
  /// is exactly [Duration.zero], so zero cannot double as "unset".
  Duration? _flingStartTime;
  double _lastFlingValue = 0;

  /// `true` while a [ChatSplineFlingSimulation] is driving inertial scroll.
  bool get isFlinging => _simulation != null;

  /// Instantaneous fling velocity in px/s, or `0` when idle.
  double flingVelocity(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return 0;
    final start = _flingStartTime ?? elapsed;
    final seconds =
        (elapsed - start).inMicroseconds / Duration.microsecondsPerSecond;
    return simulation.dx(seconds);
  }

  /// Arm a [ChatSplineFlingSimulation] at [velocity].
  void startFling(double velocity) {
    _simulation = ChatSplineFlingSimulation(velocity: velocity);
    _lastFlingValue = 0.0;
    _flingStartTime = null;
  }

  /// Stops an in-flight fling and clears simulation state.
  void cancelFling() {
    _simulation = null;
    _flingStartTime = null;
    _lastFlingValue = 0;
  }

  /// Per-frame fling delta (px). Returns `0` when idle or finished.
  double tickFling(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return 0;
    final start = _flingStartTime ??= elapsed;
    final seconds =
        (elapsed - start).inMicroseconds / Duration.microsecondsPerSecond;
    if (simulation.isDone(seconds)) {
      cancelFling();
      return 0;
    }
    final value = simulation.x(seconds);
    final delta = value - _lastFlingValue;
    _lastFlingValue = value;
    return delta;
  }
}

/// Android's `OverScroller` fling curve (`SplineOverScroller`), in logical
/// pixels.
///
/// Travels the same distance from the same initial velocity as
/// `ClampingScrollSimulation`, but keeps Android's full duration and slow
/// tail. `ClampingScrollSimulation` fits a power curve that ends after about
/// 0.83 of that duration, so a fling there settles, and idle-driven chrome
/// hides, noticeably sooner than on a native Android list.
final class ChatSplineFlingSimulation extends Simulation {
  /// A fling starting at position `0` with [velocity] in px/s.
  ChatSplineFlingSimulation({required double velocity, this.friction = 0.015}) {
    final speed = velocity.abs();
    if (speed == 0) return;
    final l = math.log(_inflexion * speed / (friction * _physicalCoeff));
    _duration = math.exp(l / (_decelerationRate - 1));
    _distance =
        velocity.sign *
        friction *
        _physicalCoeff *
        math.exp(_decelerationRate / (_decelerationRate - 1) * l);
  }

  /// Android `ViewConfiguration.getScrollFriction()`.
  final double friction;

  /// Seconds until the fling stops.
  double get duration => _duration;
  double _duration = 0;

  /// Signed travel in px.
  double get distance => _distance;
  double _distance = 0;

  static final double _decelerationRate = math.log(0.78) / math.log(0.9);
  static const double _inflexion = 0.35;

  /// Earth gravity × inches per meter × 160 logical px per inch × 0.84.
  static const double _physicalCoeff = 9.80665 * 39.37 * 160.0 * 0.84;

  static const int _samples = 100;
  static final List<double> _splinePosition = _buildSplinePosition();

  static List<double> _buildSplinePosition() {
    const startTension = 0.5;
    const endTension = 1.0;
    const p1 = startTension * _inflexion;
    const p2 = 1.0 - endTension * (1.0 - _inflexion);
    final positions = List<double>.filled(_samples + 1, 1);
    var xMin = 0.0;
    for (var i = 0; i < _samples; i++) {
      final alpha = i / _samples;
      var xMax = 1.0;
      double x;
      double coef;
      while (true) {
        x = xMin + (xMax - xMin) / 2;
        coef = 3 * x * (1 - x);
        final tx = coef * ((1 - x) * p1 + x * p2) + x * x * x;
        if ((tx - alpha).abs() < 1e-5) break;
        if (tx > alpha) {
          xMax = x;
        } else {
          xMin = x;
        }
      }
      positions[i] = coef * ((1 - x) * startTension + x) + x * x * x;
    }
    return positions;
  }

  /// Spline travel fraction and its slope at normalized time [t] in `[0, 1)`.
  static (double, double) _spline(double t) {
    final index = (_samples * t).floor();
    final tInf = index / _samples;
    final dInf = _splinePosition[index];
    final slope = (_splinePosition[index + 1] - dInf) * _samples;
    return (dInf + (t - tInf) * slope, slope);
  }

  @override
  double x(double time) {
    if (time >= duration) return distance;
    if (time <= 0) return 0;
    return distance * _spline(time / duration).$1;
  }

  @override
  double dx(double time) {
    if (time >= duration || duration == 0) return 0;
    return distance / duration * _spline(math.max(time, 0) / duration).$2;
  }

  @override
  bool isDone(double time) => time >= duration;
}
