import 'package:flutter/widgets.dart' show ClampingScrollSimulation;

/// Which boundary the bounceback spring is anchored to. Captured at start of
/// [ChatScrollPhysics.maybeStartBounceback]; per-tick reads stay locked to
/// this side so the delta does not flip sign when the dominant violator
/// switches (short-content viewport, fling composition).
enum BouncebackSide { top, bottom }

/// Default duration for overscroll spring-back after drag release.
const Duration kOverscrollBounceDuration = Duration(milliseconds: 200);

/// Owns fling simulation, drag resistance, and overscroll bounceback for the
/// chat viewport.
///
/// The render object measures boundary geometry (via [overscrollOnSide]) and
/// applies the returned deltas to the scroll anchor. This class is stateless
/// with respect to layout — it only owns the simulation timers and the
/// locked bounceback side.
///
/// **Tick composition** (owned by the render object's `_onTick`):
/// 1. Pending drag delta, optionally scaled by [applyOverscrollResistance]
/// 2. [tickFling] — inertial scroll from release velocity
/// 3. `animateTo` delta (render object; not here)
/// 4. [tickBounceback] — spring-back after overscroll release
///
/// Fling and bounceback may run in the same frame after a high-velocity
/// overscroll release; they compose additively.
class ChatScrollPhysics {
  ChatScrollPhysics({
    this.overscrollMax = 200.0,
    this.bounceDuration = kOverscrollBounceDuration,
    required double Function(BouncebackSide side) overscrollOnSide,
  }) : _overscrollOnSide = overscrollOnSide;

  /// Pixel reference for the resistance roll-off. At an overscroll of
  /// [overscrollMax], incoming delta is halved; the response is a hyperbola
  /// so very large overshoots get heavily damped.
  final double overscrollMax;

  /// Spring-back window after overscroll release. When the user releases while
  /// overscrolled, the viewport drives the anchor offset back to the boundary
  /// edge over this duration with linear interpolation.
  final Duration bounceDuration;

  /// Live boundary measurement supplied by the render object each tick.
  /// Positive top-side = oldest below top edge; negative bottom-side = newest
  /// above bottom edge.
  final double Function(BouncebackSide side) _overscrollOnSide;

  // --- Fling state ----------------------------------------------------------

  ClampingScrollSimulation? _simulation;

  /// Ticker `elapsed` at the first tick of the current fling, or `null`
  /// between flings. Nullable on purpose — a [Ticker]'s very first `elapsed`
  /// is exactly [Duration.zero], so zero cannot double as "unset".
  Duration? _flingStartTime;
  double _lastFlingValue = 0.0;

  // --- Bounceback state -----------------------------------------------------
  //
  // The boundary side is captured at start ([_bouncebackSide]) and frozen for
  // the duration of the animation; per-tick measurements read *only* that
  // side. A naive read of both sides would flip sign mid-animation in a
  // short-content viewport (e.g. a fling damps the dominant side and the
  // lesser one becomes dominant, or the bounceback itself overshoots through
  // the opposite edge). Without the side lock the per-tick delta would change
  // direction and the spring would judder / fight itself.

  bool _bouncebackActive = false;
  Duration? _bouncebackStartTime;
  double _bouncebackInitialOverscroll = 0.0;
  BouncebackSide _bouncebackSide = BouncebackSide.top;

  bool get isFlinging => _simulation != null;

  bool get isBouncing => _bouncebackActive;

  /// Arm a [ClampingScrollSimulation] at [velocity]. Does not emit scroll
  /// events — the render object calls `_cancelFling` first (for [ChatFlingEnd])
  /// then notifies [ChatFlingStart] after this returns.
  void startFling(double velocity) {
    _simulation = ClampingScrollSimulation(position: 0.0, velocity: velocity);
    _lastFlingValue = 0.0;
    _flingStartTime = null;
  }

  void cancelFling() {
    _simulation = null;
    _flingStartTime = null;
    _lastFlingValue = 0.0;
  }

  /// Damp [delta] when it would push the anchor further past a boundary —
  /// the further the overshoot, the higher the resistance. Returns [delta]
  /// untouched when the motion is back toward content, or when nothing is
  /// past a boundary yet.
  ///
  /// [signedOverscroll] comes from the render object's `_signedOverscroll()`.
  /// Pulling further past top = positive overscroll + positive delta.
  /// Pulling further past bottom = negative overscroll + negative delta.
  double applyOverscrollResistance(double delta, double signedOverscroll) {
    if (delta == 0.0) return delta;
    if (signedOverscroll == 0.0 ||
        (signedOverscroll > 0 && delta < 0) ||
        (signedOverscroll < 0 && delta > 0)) {
      return delta;
    }
    final magnitude = signedOverscroll.abs();
    final factor = 1.0 / (1.0 + magnitude / overscrollMax);
    return delta * factor;
  }

  /// Arm spring-back on [side] starting from [overscroll]. No-op when zero.
  /// The render object picks the dominant violator before calling.
  void maybeStartBounceback(double overscroll, BouncebackSide side) {
    if (overscroll == 0.0) return;
    _bouncebackActive = true;
    _bouncebackStartTime = null;
    _bouncebackInitialOverscroll = overscroll;
    _bouncebackSide = side;
  }

  void cancelBounceback() {
    if (!_bouncebackActive) return;
    _bouncebackActive = false;
    _bouncebackStartTime = null;
  }

  /// Returns the combined fling + bounceback delta for one ticker frame.
  double tick(Duration elapsed) => tickFling(elapsed) + tickBounceback(elapsed);

  /// Fling simulation delta for this tick. Clears [_simulation] when done.
  /// The render object detects the `isFlinging` → idle transition and emits
  /// [ChatFlingEnd] — this method does not notify the controller.
  double tickFling(Duration elapsed) {
    var delta = 0.0;
    final simulation = _simulation;
    if (simulation != null) {
      final startTime = _flingStartTime ??= elapsed;
      final seconds =
          (elapsed - startTime).inMicroseconds / Duration.microsecondsPerSecond;
      if (simulation.isDone(seconds)) {
        _simulation = null;
        _flingStartTime = null;
        _lastFlingValue = 0.0;
      } else {
        final value = simulation.x(seconds);
        delta += value - _lastFlingValue;
        _lastFlingValue = value;
      }
    }
    return delta;
  }

  /// Bounceback spring delta for this tick. See [_tickBounceback].
  double tickBounceback(Duration elapsed) => _tickBounceback(elapsed);

  /// Drive one tick of the bounceback animation. Returns the scroll delta to
  /// feed into `applyScrollDelta`; clears [_bouncebackActive] once the
  /// animation has fully settled the anchor back against the boundary.
  ///
  /// Reads overscroll on the *locked* side only. A naive read of both sides
  /// would flip sign whenever the dominant boundary switched mid-animation
  /// (e.g. the spring overshoots through zero and past the opposite edge, or
  /// a composed fling damps one side faster than the other), driving the delta
  /// in the wrong direction for the remainder of the window — visible as
  /// judder or a stuck spring.
  double _tickBounceback(Duration elapsed) {
    if (!_bouncebackActive) return 0.0;
    final start = _bouncebackStartTime ??= elapsed;
    final totalUs = bounceDuration.inMicroseconds;
    final elapsedUs = (elapsed - start).inMicroseconds;
    final t = (elapsedUs / totalUs).clamp(0.0, 1.0);
    // Linear ramp toward zero overscroll; sign matches the direction we need
    // to push the anchor (negative when past top, positive when past bottom —
    // opposite of the overscroll's sign).
    final remainingTarget = _bouncebackInitialOverscroll * (1.0 - t);
    final currentOverscroll = _overscrollOnSide(_bouncebackSide);
    // Move from current → remainingTarget by emitting (target - current).
    // `applyScrollDelta(+px)` shifts the anchor down (reveals older); that
    // *increases* topY (positive overscroll). To shrink positive overscroll
    // we need a negative delta. Hence the sign flip:
    final bounceDelta = -(currentOverscroll - remainingTarget);
    if (t >= 1.0) cancelBounceback();
    return bounceDelta;
  }
}
