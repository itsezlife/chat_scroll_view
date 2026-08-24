import 'package:flutter/widgets.dart' show ClampingScrollSimulation;

/// Inertial fling for the panel catalog viewport.
///
/// Owns [ClampingScrollSimulation] start / tick / cancel. Does **not** own
/// overscroll stretch, near-path animate, or stitch.
///
/// Call [startFling] from drag-end when content has travel range;
/// [tickFling] from the viewport ticker; [cancelFling] on drag-start,
/// fling-cancel pointer-down, wheel, jump, or when a scroll wall is hit.
final class CatalogScrollPhysics {
  /// Creates idle fling physics.
  CatalogScrollPhysics();

  ClampingScrollSimulation? _simulation;

  /// Ticker `elapsed` at the first tick of the current fling, or `null`
  /// between flings. Nullable on purpose — a [Ticker]'s first `elapsed` is
  /// [Duration.zero], so zero cannot mean "unset".
  Duration? _flingStartTime;
  double _lastFlingValue = 0;

  /// `true` while a [ClampingScrollSimulation] is driving inertial scroll.
  bool get isFlinging => _simulation != null;

  /// Arms a [ClampingScrollSimulation] at [velocity] (px/s in **content
  /// offset** space: positive velocity increases [PanelCatalogController.offset]).
  void startFling(double velocity) {
    _simulation = ClampingScrollSimulation(position: 0, velocity: velocity);
    _lastFlingValue = 0;
    _flingStartTime = null;
  }

  /// Stops an in-flight fling. Idempotent.
  void cancelFling() {
    _simulation = null;
    _flingStartTime = null;
    _lastFlingValue = 0;
  }

  /// Per-frame fling delta in content-offset space. `0` when idle or finished.
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
