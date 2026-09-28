import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_motion.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

/// **Stretch** edge-effect state: the Android edge stretch over a clamped
/// chat viewport.
///
/// Owns the stretch ratio ([overscroll] in `[-1, 1]`), the return spring,
/// and the scale-from-edge [paintTransform]. Never mutates scroll layout —
/// callers feed only the unconsumed remainder at a reached pin.
///
/// **Pull**: [pull] accumulates unconsumed pointer dy into [overscroll].
/// Positive stretch scales from the top edge; negative from the bottom.
///
/// **Reverse motion**: [claim] passes every pixel through to content and
/// starts the release once content actually travels away from the stretched
/// edge ([releaseIntoContent]).
///
/// **Release**: [onDragEnd] springs back when stretch is painted. A strong
/// reverse velocity (opposite [overscroll]) clears stretch so content can
/// fling. [absorbImpact] arms a spring when an inertial fling hits a wall.
///
/// Spring and intensity come from [ChatEdgeEffect$Stretch]; the curve
/// shape, release velocity floor, and impact scaling match Flutter's
/// stretching overscroll indicator (time factor 0.8).
@internal
final class ChatStretchOverscroll implements ChatEdgeEffectState {
  /// Idle stretch tuned by [effect].
  ChatStretchOverscroll([this.effect = const ChatEdgeEffect$Stretch()])
    : _spring = SpringDescription.withDampingRatio(
        mass: 1,
        stiffness:
            effect.naturalFrequency *
            effect.naturalFrequency *
            _timeCorrectionFactor *
            _timeCorrectionFactor,
        ratio: effect.dampingRatio,
      );

  /// Parameters this stretch runs with.
  final ChatEdgeEffect$Stretch effect;

  final SpringDescription _spring;

  /// Paint stretch in `[-1, 1]`. Positive = scale from the top edge.
  double get overscroll => _overscroll;
  double _overscroll = 0;

  /// Running pull sum for the current gesture, in pixels.
  double _totalPullPx = 0;

  double _interruptedOverscroll = 0;
  SpringSimulation? _simulation;
  Duration? _simStart;
  int _tickFrame = 0;

  static const double _exponentialScalar = math.e / 0.33;
  static const double _absorbImpactVelocityFriction = 1 / 3000;
  static const double _maxAbsorbImpactVelocity = 1.25;

  /// Release velocity below this (px/s) is a soft release, not a flick.
  static const double _minReleaseVelocity = 50;

  /// Travel back into content below this (px) is sub-pixel noise — the last
  /// pixels of travel toward the stretched edge, not a return from it.
  static const double _minReleaseTravelPx = 1;

  /// Below this, leftover stretch is treated as rest.
  static const double _minPaintStretch = 0.004;
  static const double _timeCorrectionFactor = 0.8;

  @override
  bool get isActive =>
      _simulation != null || _overscroll.abs() > _minPaintStretch;

  @override
  bool get isSpringing => _simulation != null;

  @override
  void onDragStart() {
    _simulation = null;
    _simStart = null;
    if (_overscroll.abs() < _minPaintStretch) {
      _overscroll = 0;
      _interruptedOverscroll = 0;
    } else {
      _interruptedOverscroll = _overscroll;
    }
    _totalPullPx = 0;
    fine(.overscroll, 'drag.start', {
      'stretch': LogFormat.ratio(_overscroll),
      'interrupted': LogFormat.ratio(_interruptedOverscroll),
    });
  }

  /// Passes [delta] through untouched. Starts the release when [delta]
  /// runs opposite the stretch and content consumes more than a pixel of it
  /// without spilling past the opposite pin — a spill lands in [pull]
  /// instead, which unwinds the gesture's pull continuously.
  @override
  double claim(double delta, {required double travel}) {
    if (_overscroll == 0 || delta.sign == _overscroll.sign) return delta;
    final consumed = math.min(delta.abs(), travel);
    final spill = delta.abs() - consumed;
    if (consumed > _minReleaseTravelPx && spill <= _minReleaseTravelPx) {
      releaseIntoContent();
    }
    return delta;
  }

  @override
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
    final linear = effect.intensity * absDistance;
    final exponential =
        effect.intensity * (1 - math.exp(-absDistance * _exponentialScalar));
    _overscroll = clampDouble(
      normalized.sign * (linear + exponential) + _interruptedOverscroll,
      -1,
      1,
    );
    fine(.overscroll, 'pull', {
      'unconsumed': LogFormat.f(unconsumedPx),
      'travel': LogFormat.f(travel),
      'fits': fits,
      'totalPx': LogFormat.f(_totalPullPx),
      'vh': LogFormat.f(viewportHeight),
      'norm': LogFormat.ratio(normalized),
      'stretch': LogFormat.ratio(_overscroll),
    });
  }

  /// Returns `true` only when no stretch remains afterwards.
  ///
  /// No-op (fling allowed) when there is no painted stretch — mid-content
  /// flicks MUST NOT start a return spring.
  ///
  /// - Reverse velocity (opposite [overscroll]): clear stretch so content
  ///   can fling.
  /// - Same-direction velocity: [absorbImpact] — briefly deepen the stretch
  ///   then spring back (edge fling), instead of slamming with inverted
  ///   fling velocity.
  /// - Near-zero velocity: soft spring from the current stretch.
  @override
  bool onDragEnd(double velocity) {
    _totalPullPx = 0;
    if (_overscroll.abs() < _minPaintStretch) {
      _interruptedOverscroll = 0;
      _overscroll = 0;
      _simulation = null;
      _simStart = null;
      fine(.overscroll, 'drag.end.idle', {'v': LogFormat.f(velocity)});
      return true;
    }
    final flick = velocity.abs() >= _minReleaseVelocity && velocity.sign != 0;
    if (flick && velocity.sign != _overscroll.sign) {
      fine(.overscroll, 'drag.end.releaseFling', {
        'v': LogFormat.f(velocity),
        'from': LogFormat.ratio(_overscroll),
      });
      _overscroll = 0;
      _interruptedOverscroll = 0;
      _simulation = null;
      _simStart = null;
      return true;
    }
    if (flick) {
      fine(.overscroll, 'drag.end.absorb', {
        'v': LogFormat.f(velocity),
        'from': LogFormat.ratio(_overscroll),
      });
      absorbImpact(velocity);
      return false;
    }
    _startSpring(0);
    fine(.overscroll, 'drag.end.spring', {
      'v': LogFormat.f(velocity),
      'scaledV': LogFormat.ratio(0),
      'from': LogFormat.ratio(_overscroll),
    });
    return false;
  }

  /// Ignores leftover velocity below the release floor.
  @override
  void absorbImpact(double velocity) {
    if (velocity.abs() < _minReleaseVelocity) return;
    final scaled = clampDouble(
      velocity * _absorbImpactVelocityFriction,
      -_maxAbsorbImpactVelocity,
      _maxAbsorbImpactVelocity,
    );
    _startSpring(scaled);
    fine(.overscroll, 'absorb', {
      'v': LogFormat.f(velocity),
      'scaledV': LogFormat.ratio(scaled),
      'from': LogFormat.ratio(_overscroll),
    });
  }

  /// Content travelled back from the stretched edge — release any live
  /// stretch once.
  ///
  /// A running return spring is left alone; restarting it every drag tick
  /// pins spring time at zero and keeps leftover stretch alive across frames.
  void releaseIntoContent() {
    if (_simulation != null) return;
    if (_overscroll.abs() < _minPaintStretch) {
      _overscroll = 0;
      _interruptedOverscroll = 0;
      _totalPullPx = 0;
      return;
    }
    fine(.overscroll, 'release.intoContent', {
      'from': LogFormat.ratio(_overscroll),
    });
    _totalPullPx = 0;
    _startSpring(0);
  }

  @override
  void reset() {
    if (!isActive && _totalPullPx == 0) return;
    fine(.overscroll, 'reset', {'from': LogFormat.ratio(_overscroll)});
    _overscroll = 0;
    _totalPullPx = 0;
    _interruptedOverscroll = 0;
    _simulation = null;
    _simStart = null;
  }

  @override
  bool tick(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return false;
    final start = _simStart ??= elapsed;
    final seconds =
        (elapsed - start).inMicroseconds / Duration.microsecondsPerSecond;
    if (simulation.isDone(seconds)) {
      fine(.overscroll, 'spring.done', {'t': LogFormat.ratio(seconds)});
      _overscroll = 0;
      _interruptedOverscroll = 0;
      _simulation = null;
      _simStart = null;
      return false;
    }
    _overscroll = clampDouble(simulation.x(seconds), -1, 1);
    if (++_tickFrame % 8 == 1) {
      fine(.overscroll, 'spring.tick', {
        't': LogFormat.ratio(seconds),
        'stretch': LogFormat.ratio(_overscroll),
      });
    }
    return true;
  }

  /// Scales `1 + |overscroll|` vertically about the pressed edge: the top
  /// edge for positive stretch, the bottom edge for negative.
  @override
  Matrix4? paintTransform(Size size) {
    final s = _overscroll;
    if (s.abs() <= precisionErrorTolerance) return null;
    final originY = s >= 0 ? 0.0 : size.height;
    return Matrix4.identity()
      ..translateByDouble(0, originY, 0, 1)
      ..scaleByDouble(1, 1.0 + s.abs(), 1, 1)
      ..translateByDouble(0, -originY, 0, 1);
  }

  void _startSpring(double scaledVelocity) {
    _interruptedOverscroll = 0;
    _simulation = SpringSimulation(
      _spring,
      _overscroll,
      0,
      scaledVelocity * _timeCorrectionFactor,
    );
    _simStart = null;
  }
}
