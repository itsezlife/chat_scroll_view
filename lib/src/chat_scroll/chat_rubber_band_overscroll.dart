import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_motion.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

/// **Rubber-band** edge-effect state: the edge translate over a clamped
/// chat viewport.
///
/// Owns the painted [displacement] (px), the return spring, and the
/// translate [paintTransform]. Never mutates scroll layout — callers feed
/// only the unconsumed remainder at a reached pin.
///
/// **Pull**: [displacement] is always the band of some finger pull `x`: `d·c·x / (d + c·x)`, with `d` the viewport height and
/// `c` the [ChatEdgeEffect$RubberBand.resistance]. [pull] and [claim] map
/// the displacement back to its pull, add the new motion, and map forward
/// again — so resistance depends only on where the layer is, never on how
/// it got there (a drag, a caught spring, or a fling overshoot). That round
/// trip needs an invertible curve; `BouncingScrollPhysics.frictionFactor`
/// is applied per delta and has no inverse.
///
/// **Reverse motion**: [claim] consumes motion back toward content along
/// the same curve and hands layout only what is left past the pin.
///
/// **Release**: [onDragEnd] hands a flick toward content to the content
/// fling, which unwinds the displacement through [claim] before content
/// moves. Any other visible displacement springs back at the layer's own
/// speed (the release velocity times the band's slope) and blocks the
/// content fling. [absorbImpact]
/// launches the same spring from the pin with a fling's leftover velocity.
/// A spring ends at the pin; it never crosses into the opposite edge.
@internal
final class ChatRubberBandOverscroll implements ChatEdgeEffectState {
  /// Idle rubber-band tuned by [effect].
  ChatRubberBandOverscroll([this.effect = const ChatEdgeEffect$RubberBand()])
    : _spring = SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: effect.naturalFrequency * effect.naturalFrequency,
        ratio: effect.dampingRatio,
      );

  /// Parameters this rubber-band runs with.
  final ChatEdgeEffect$RubberBand effect;

  final SpringDescription _spring;

  /// Painted translate of the message layer in px. Positive moves content
  /// down past the oldest (top) edge; negative moves it up past the newest
  /// (bottom) edge.
  double get displacement => _displacement;
  double _displacement = 0;

  /// Viewport height of the last [pull] or [claim]; `0` before either.
  double _viewportHeight = 0;

  SpringSimulation? _simulation;
  final ChatSpringClock _clock = ChatSpringClock();

  /// Side of rest the running spring started on (`±1`). The spring stops
  /// when the displacement reaches or crosses rest from this side.
  double _springSide = 0;

  int _tickFrame = 0;

  /// Below this (px), a displacement with no spring is treated as rest.
  static const double _restPx = 0.5;

  /// Leftover fling velocity below this (px/s) is a fling that ran out at
  /// the pin, not an impact.
  static const double _minImpactVelocity = 50;

  /// Spring stop point: the default `0.001` px tolerance would keep the
  /// ticker running through an invisible sub-pixel tail.
  static const Tolerance _tolerance = Tolerance(distance: 0.5, velocity: 10);

  @override
  bool get isActive => _simulation != null || _displacement.abs() > _restPx;

  @override
  bool get isSpringing => _simulation != null;

  @override
  void onDragStart() {
    _stopSpring();
    if (_displacement.abs() <= _restPx) _displacement = 0;
    fine(.overscroll, 'band.drag.start', {
      'offset': LogFormat.f(_displacement),
    });
  }

  /// Consumes motion toward content along the band curve. Returns `0`
  /// while the layer is still displaced after [delta], or the part of
  /// [delta] left once it reaches the pin. [travel] plays no part: the
  /// layer always returns to the pin before content moves.
  @override
  double claim(double delta, double viewportHeight, {required double travel}) {
    if (_displacement == 0 ||
        delta.sign == _displacement.sign ||
        viewportHeight <= 0) {
      return delta;
    }
    _stopSpring();
    _viewportHeight = viewportHeight;
    final remainingPull =
        _pullFor(_displacement.abs(), viewportHeight) - delta.abs();
    if (remainingPull > 0) {
      _displacement =
          _displacement.sign * _displacementFor(remainingPull, viewportHeight);
      return 0;
    }
    _displacement = 0;
    return delta.sign * -remainingPull;
  }

  @override
  void pull(
    double unconsumedPx,
    double viewportHeight, {
    double travel = 0,
    bool fits = false,
  }) {
    if (unconsumedPx == 0 || viewportHeight <= 0) return;
    _stopSpring();
    _viewportHeight = viewportHeight;
    final signedPull =
        _displacement.sign * _pullFor(_displacement.abs(), viewportHeight) +
        unconsumedPx;
    _displacement =
        signedPull.sign * _displacementFor(signedPull.abs(), viewportHeight);
    fine(.overscroll, 'band.pull', {
      'unconsumed': LogFormat.f(unconsumedPx),
      'fits': fits,
      'vh': LogFormat.f(viewportHeight),
      'offset': LogFormat.f(_displacement),
    });
  }

  /// Returns `true` when the layer is at rest, or when [velocity] flicks
  /// back toward content.
  ///
  /// A flick toward content keeps the displacement for the content fling
  /// to unwind through [claim], so the flick's momentum carries into
  /// content. The caller MUST keep feeding that fling through [claim], and
  /// MUST release again (`onDragEnd(0)`) if the fling does not start or
  /// ends while the layer is still displaced.
  ///
  /// Any other visible displacement springs back carrying the layer's own
  /// speed — [velocity] scaled by the band's slope where the layer is — so
  /// a release into the edge stretches a little further first without
  /// speeding up. No content fling starts.
  @override
  bool onDragEnd(double velocity) {
    if (_displacement.abs() <= _restPx) {
      _displacement = 0;
      _stopSpring();
      fine(.overscroll, 'band.drag.end.idle', {'v': LogFormat.f(velocity)});
      return true;
    }
    if (velocity.abs() >= _minImpactVelocity &&
        velocity.sign != _displacement.sign) {
      _stopSpring();
      fine(.overscroll, 'band.drag.end.carry', {
        'v': LogFormat.f(velocity),
        'from': LogFormat.f(_displacement),
      });
      return true;
    }
    final layerVelocity = velocity * _slopeAt(_displacement.abs());
    _startSpring(layerVelocity);
    fine(.overscroll, 'band.drag.end.spring', {
      'v': LogFormat.f(velocity),
      'layerV': LogFormat.f(layerVelocity),
      'from': LogFormat.f(_displacement),
    });
    return false;
  }

  /// Ignores leftover velocity below the impact floor.
  @override
  void absorbImpact(double velocity) {
    if (velocity.abs() < _minImpactVelocity) return;
    _startSpring(velocity);
    fine(.overscroll, 'band.absorb', {
      'v': LogFormat.f(velocity),
      'from': LogFormat.f(_displacement),
    });
  }

  @override
  void reset() {
    if (!isActive && _displacement == 0) return;
    fine(.overscroll, 'band.reset', {'from': LogFormat.f(_displacement)});
    _displacement = 0;
    _stopSpring();
  }

  @override
  bool tick(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) {
      _clock.idleTick = elapsed;
      return false;
    }
    final seconds = _clock.secondsAt(elapsed);
    final x = simulation.x(seconds);
    if (simulation.isDone(seconds) || (seconds > 0 && x * _springSide <= 0)) {
      fine(.overscroll, 'band.spring.done', {'t': LogFormat.ratio(seconds)});
      _displacement = 0;
      _stopSpring();
      return false;
    }
    _displacement = x;
    if (++_tickFrame % 8 == 1) {
      fine(.overscroll, 'band.spring.tick', {
        't': LogFormat.ratio(seconds),
        'offset': LogFormat.f(_displacement),
      });
    }
    return true;
  }

  /// Translates the message layer by [displacement]; [size] plays no part.
  @override
  Matrix4? paintTransform(Size size) {
    if (_displacement.abs() <= precisionErrorTolerance) return null;
    return Matrix4.translationValues(0, _displacement, 0);
  }

  /// Launches the return spring from the current displacement with
  /// [velocity], uncapped: a critically damped spring peaks at
  /// `v / (ω·e)`, so the overshoot keeps scaling with the impact.
  void _startSpring(double velocity) {
    _springSide = _displacement != 0 ? _displacement.sign : velocity.sign;
    _simulation = SpringSimulation(
      _spring,
      _displacement,
      0,
      velocity,
      tolerance: _tolerance,
    );
    _clock.restart();
  }

  void _stopSpring() {
    _simulation = null;
    _clock.restart();
  }

  /// Layer px per finger px at [displacement]: the band's derivative,
  /// `c · ((d − b) / d)²`. `1` before any viewport height is known.
  double _slopeAt(double displacement) {
    final d = _viewportHeight;
    if (d <= 0) return 1;
    final b = math.min(displacement, d);
    final remaining = (d - b) / d;
    return effect.resistance * remaining * remaining;
  }

  /// Band displacement for a finger pull of [pull] px.
  double _displacementFor(double pull, double viewportHeight) {
    final c = effect.resistance;
    return viewportHeight * c * pull / (viewportHeight + c * pull);
  }

  /// Finger pull that yields a band displacement of [displacement] px —
  /// the inverse of [_displacementFor]. A spring overshoot can exceed what
  /// any pull reaches (the curve approaches the viewport height), so the
  /// input is held just inside it.
  double _pullFor(double displacement, double viewportHeight) {
    final b = math.min(displacement, viewportHeight * 0.999);
    return viewportHeight * b / (effect.resistance * (viewportHeight - b));
  }
}
