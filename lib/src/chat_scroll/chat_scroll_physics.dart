import 'package:flutter/widgets.dart' show ClampingScrollSimulation;

/// Inertial fling for the chat viewport.
///
/// Owns [ClampingScrollSimulation] start / tick / cancel. Does **not** own
/// boundary stretch — that lives on [ChatStretchOverscroll] (paint-only).
///
/// **Host wiring**: call [startFling] from drag-end when stretch is inactive
/// and content has travel range; [tickFling] from the viewport ticker;
/// [cancelFling] on drag-start, jump, or when a pin wall is hit.
class ChatScrollPhysics {
  /// Creates fling physics.
  ChatScrollPhysics();

  ClampingScrollSimulation? _simulation;

  /// Ticker `elapsed` at the first tick of the current fling, or `null`
  /// between flings. Nullable on purpose — a [Ticker]'s very first `elapsed`
  /// is exactly [Duration.zero], so zero cannot double as "unset".
  Duration? _flingStartTime;
  double _lastFlingValue = 0;

  /// `true` while a [ClampingScrollSimulation] is driving inertial scroll.
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

  /// Arm a [ClampingScrollSimulation] at [velocity].
  void startFling(double velocity) {
    _simulation = ClampingScrollSimulation(position: 0, velocity: velocity);
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
