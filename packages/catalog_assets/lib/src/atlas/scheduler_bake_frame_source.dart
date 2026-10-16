import 'dart:math' as math;
import 'dart:ui';

import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:flutter/scheduler.dart';

/// The [BakeFrameSource] for a running app: frames come from the
/// [SchedulerBinding], the budget from the display of [view], and the cost
/// from the engine's frame timings.
///
/// A request schedules a frame and runs its callback after that frame has been
/// built and handed to the raster thread, so the bake step spends time the
/// frame has already finished with instead of delaying its layout. Baking
/// never keeps a frame loop alive by itself: with nothing requested, an idle
/// app draws nothing.
///
/// The engine delivers timings in batches, a few frames late. The slowest
/// thread of everything received since the last report is passed on once, so
/// a slow frame is reacted to once and not for as long as it stays the latest.
///
/// Call [dispose] when the bake is over.
final class SchedulerBakeFrameSource implements BakeFrameSource {
  /// Creates a source measuring frames of [view], on [binding] (the global
  /// one by default).
  SchedulerBakeFrameSource({
    required FlutterView view,
    SchedulerBinding? binding,
  }) : _view = view,
       _binding = binding ?? SchedulerBinding.instance {
    _binding.addTimingsCallback(_onTimings);
  }

  /// Refresh rate assumed when the display does not report one.
  static const double fallbackRefreshRate = 60;

  final FlutterView _view;
  final SchedulerBinding _binding;
  Duration? _unreportedCost;

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final cost = timing.buildDuration > timing.rasterDuration
          ? timing.buildDuration
          : timing.rasterDuration;
      _unreportedCost = _unreportedCost == null
          ? cost
          : Duration(
              microseconds: math.max(
                _unreportedCost!.inMicroseconds,
                cost.inMicroseconds,
              ),
            );
    }
  }

  @override
  BakeFrameCancel requestFrame(BakeFrameCallback onFrame) {
    var live = true;
    // A post-frame callback cannot be removed, so cancelling only disarms it.
    _binding
      ..scheduleFrame()
      ..addPostFrameCallback((_) {
        if (!live) return;
        live = false;
        final rate = _view.display.refreshRate;
        final cost = _unreportedCost;
        _unreportedCost = null;
        onFrame(
          BakeFrame(
            budget: Duration(
              microseconds:
                  (Duration.microsecondsPerSecond /
                          (rate > 0 ? rate : fallbackRefreshRate))
                      .round(),
            ),
            cost: cost,
          ),
        );
      });
    return () => live = false;
  }

  /// Stops listening to frame timings.
  void dispose() => _binding.removeTimingsCallback(_onTimings);
}
