import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

/// Paint-time edge stretch for a clamped chat viewport.
///
/// Owns the stretch ratio ([overscroll] in `[-1, 1]`), the return spring, and
/// the scale-from-edge [paintMatrix]. Does **not** mutate scroll layout —
/// callers feed only the unconsumed remainder at a reached pin.
///
/// **Pull**: [pull] accumulates unconsumed pointer dy into [overscroll].
/// Positive stretch scales from the top edge; negative from the bottom.
///
/// **Release**: [onDragEnd] springs back when stretch is painted. A strong
/// reverse velocity (opposite [overscroll]) clears stretch so the host can
/// fling into content. [releaseIntoContent] starts a return spring once when
/// travel moves away from the stretched edge. [absorbImpact] arms a spring
/// when an inertial fling hits a wall.
///
/// **Paint**: hosts MUST apply [paintMatrix] only to message children.
/// Viewport-fixed chrome (floating date header, scrollbar) MUST stay outside
/// the transform.
///
/// Constants match the platform stretch intensity / spring used by Flutter's
/// stretching overscroll indicator (natural frequency 24.657, damping 0.98,
/// time factor 0.8).
class ChatStretchOverscroll {
  /// Creates a stretch controller. Pass [log] from the viewport host.
  ChatStretchOverscroll({ChatScrollDevLog? log})
    : log = log ?? ChatScrollDevLog('ChatScrollOverscroll');

  /// Stretch diagnostics — filter `ChatScrollOverscroll`.
  final ChatScrollDevLog log;

  /// Paint stretch in `[-1, 1]`. Positive = scale from the top edge.
  double overscroll = 0;

  /// Running pull sum for the current gesture, in pixels.
  double _totalPullPx = 0;

  double _interruptedOverscroll = 0;
  SpringSimulation? _simulation;
  Duration? _simStart;

  static const double _exponentialScalar = math.e / 0.33;
  static const double _stretchIntensity = 0.016;
  static const double _absorbImpactVelocityFriction = 1 / 3000;
  static const double _maxAbsorbImpactVelocity = 1.25;

  /// Below this, leftover stretch is treated as rest.
  static const double _minPaintStretch = 0.004;
  static const double _naturalFrequency = 24.657;
  static const double _dampingRatio = 0.98;
  static const double _timeCorrectionFactor = 0.8;
  static const double _stiffness = _naturalFrequency * _naturalFrequency;

  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: _stiffness * _timeCorrectionFactor * _timeCorrectionFactor,
    ratio: _dampingRatio,
  );

  /// `true` while a stretch is painted or a return spring is running.
  bool get isActive =>
      _simulation != null || overscroll.abs() > _minPaintStretch;

  /// Finger down: keep a *visible* stretch, stop the return spring.
  void onDragStart() {
    _simulation = null;
    _simStart = null;
    if (overscroll.abs() < _minPaintStretch) {
      overscroll = 0;
      _interruptedOverscroll = 0;
    } else {
      _interruptedOverscroll = overscroll;
    }
    _totalPullPx = 0;
    log.event('drag.start', {
      'stretch': DevLogFormat.ratio(overscroll),
      'interrupted': DevLogFormat.ratio(_interruptedOverscroll),
    });
  }

  /// Unconsumed pointer dy (same sign as chat delta: + = content down).
  ///
  /// [travel] is remaining pin distance *before* this delta (0 = already
  /// at that edge). [fits] is short-content (zero travel on both pins).
  void pull(
    double unconsumedPx,
    double viewportHeight, {
    double travel = 0,
    bool fits = false,
  }) {
    if (unconsumedPx == 0 || viewportHeight <= 0) return;
    _simulation = null;
    _simStart = null;
    _totalPullPx += unconsumedPx;
    final normalized = clampDouble(_totalPullPx / viewportHeight, -1, 1);
    final absDistance = normalized.abs();
    final linear = _stretchIntensity * absDistance;
    final exponential =
        _stretchIntensity * (1 - math.exp(-absDistance * _exponentialScalar));
    overscroll = clampDouble(
      normalized.sign * (linear + exponential) + _interruptedOverscroll,
      -1,
      1,
    );
    log.event('pull', {
      'unconsumed': DevLogFormat.f(unconsumedPx),
      'travel': DevLogFormat.f(travel),
      'fits': fits,
      'totalPx': DevLogFormat.f(_totalPullPx),
      'vh': DevLogFormat.f(viewportHeight),
      'norm': DevLogFormat.ratio(normalized),
      'stretch': DevLogFormat.ratio(overscroll),
    });
  }

  /// Finger up. [velocity] is drag primary velocity (px/s, + = down).
  ///
  /// No-op when there is no painted stretch — mid-content flicks MUST NOT
  /// start a return spring.
  ///
  /// - Reverse velocity (opposite [overscroll]): clear stretch so the host
  ///   can fling into content.
  /// - Same-direction velocity: [absorbImpact] — briefly deepen the stretch
  ///   then spring back (edge fling), instead of slamming with inverted
  ///   fling velocity.
  /// - Near-zero velocity: soft spring from the current stretch (`velocity` 0).
  void onDragEnd(double velocity) {
    _totalPullPx = 0;
    if (overscroll.abs() < _minPaintStretch) {
      _interruptedOverscroll = 0;
      overscroll = 0;
      _simulation = null;
      _simStart = null;
      log.event('drag.end.idle', {'v': DevLogFormat.f(velocity)});
      return;
    }
    if (velocity.abs() >= 50 &&
        velocity.sign != 0 &&
        overscroll.sign != 0 &&
        velocity.sign != overscroll.sign) {
      log.event('drag.end.releaseFling', {
        'v': DevLogFormat.f(velocity),
        'from': DevLogFormat.ratio(overscroll),
      });
      overscroll = 0;
      _interruptedOverscroll = 0;
      _simulation = null;
      _simStart = null;
      return;
    }
    if (velocity.abs() >= 50 &&
        velocity.sign != 0 &&
        overscroll.sign != 0 &&
        velocity.sign == overscroll.sign) {
      log.event('drag.end.absorb', {
        'v': DevLogFormat.f(velocity),
        'from': DevLogFormat.ratio(overscroll),
      });
      absorbImpact(velocity);
      return;
    }
    _startSpring(0);
    log.event('drag.end.spring', {
      'v': DevLogFormat.f(velocity),
      'scaledV': DevLogFormat.ratio(0),
      'from': DevLogFormat.ratio(overscroll),
    });
  }

  /// Fling hit a clamped edge. [velocity] is remaining fling velocity (px/s).
  void absorbImpact(double velocity) {
    if (velocity.abs() < 50) return;
    final scaled = clampDouble(
      velocity * _absorbImpactVelocityFriction,
      -_maxAbsorbImpactVelocity,
      _maxAbsorbImpactVelocity,
    );
    _startSpring(scaled);
    log.event('absorb', {
      'v': DevLogFormat.f(velocity),
      'scaledV': DevLogFormat.ratio(scaled),
      'from': DevLogFormat.ratio(overscroll),
    });
  }

  /// Scrolled back into content — release any live stretch once.
  ///
  /// A running return spring is left alone; restarting it every drag tick
  /// pins spring time at zero and keeps leftover stretch alive across frames.
  void releaseIntoContent() {
    if (_simulation != null) return;
    if (overscroll.abs() < _minPaintStretch) {
      overscroll = 0;
      _interruptedOverscroll = 0;
      _totalPullPx = 0;
      return;
    }
    log.event('release.intoContent', {'from': DevLogFormat.ratio(overscroll)});
    _totalPullPx = 0;
    _startSpring(0);
  }

  /// Hard reset (overlay, controller swap, programmatic jump).
  void reset() {
    if (!isActive && _totalPullPx == 0) return;
    log.event('reset', {'from': DevLogFormat.ratio(overscroll)});
    overscroll = 0;
    _totalPullPx = 0;
    _interruptedOverscroll = 0;
    _simulation = null;
    _simStart = null;
  }

  /// Advance the return spring. Returns `true` if paint is still needed.
  bool tick(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return false;
    final start = _simStart ??= elapsed;
    final seconds =
        ((elapsed - start).inMicroseconds / Duration.microsecondsPerSecond) *
        1.0;
    if (simulation.isDone(seconds)) {
      log.event('spring.done', {'t': DevLogFormat.ratio(seconds)});
      overscroll = 0;
      _interruptedOverscroll = 0;
      _simulation = null;
      _simStart = null;
      return false;
    }
    overscroll = clampDouble(simulation.x(seconds), -1, 1);
    if (log.bumpTickFrame() % 8 == 1) {
      log.event('spring.tick', {
        't': DevLogFormat.ratio(seconds),
        'stretch': DevLogFormat.ratio(overscroll),
      });
    }
    return true;
  }

  /// Scale-from-edge matrix for [PaintingContext.pushTransform].
  ///
  /// Apply only to message content. Viewport-fixed chrome MUST NOT use this
  /// matrix.
  Matrix4 paintMatrix(Size size) {
    final s = overscroll;
    final originY = s >= 0 ? 0.0 : size.height;
    final matrix = Matrix4.identity();
    matrix
      ..translateByDouble(0, originY, 0, 1)
      ..scaleByDouble(1, 1.0 + s.abs(), 1, 1)
      ..translateByDouble(0, -originY, 0, 1);
    return matrix;
  }

  void _startSpring(double scaledVelocity) {
    _interruptedOverscroll = 0;
    _simulation = SpringSimulation(
      _spring,
      overscroll,
      0,
      scaledVelocity * _timeCorrectionFactor,
    );
    _simStart = null;
  }
}
