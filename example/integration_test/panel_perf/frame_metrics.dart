/// Frame-time arithmetic for the panel acceptance test.
///
/// Pure Dart on purpose: the on-device test, the host-side driver and the unit
/// tests under `test/panel_perf/` all share it, and none of the arithmetic
/// needs a device.
library;

import 'dart:math' as math;

/// Assumed rate when the display reports none (zero, negative or NaN).
const double kFallbackRefreshRateHz = 60;

/// One vsync interval in milliseconds for a display at [refreshRateHz].
///
/// A display that reports no usable rate is treated as 60 Hz, the laxest
/// budget in use; the report records the reported rate so the substitution is
/// visible.
double vsyncBudgetMs(double refreshRateHz) {
  final usable = refreshRateHz.isFinite && refreshRateHz > 0
      ? refreshRateHz
      : kFallbackRefreshRateHz;
  return 1000 / usable;
}

/// Nearest-rank percentile of [values] for [fraction] in `(0, 1]`.
///
/// No interpolation: the result is always one of the measured frames, so a
/// "p99 at most 2 ms" claim names a frame that really took that long.
double percentile(List<double> values, double fraction) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'must not be empty');
  }
  final sorted = [...values]..sort();
  final rank = (fraction * sorted.length).ceil();
  return sorted[(rank - 1).clamp(0, sorted.length - 1)];
}

/// Build, raster and total time of one frame, in milliseconds.
final class FrameSample {
  const FrameSample({
    required this.buildMs,
    required this.rasterMs,
    this.totalMs = 0,
  });

  final double buildMs;
  final double rasterMs;

  /// Vsync-to-raster-finish span; informational, not part of any criterion.
  final double totalMs;

  /// The slower of the two threads: what decides whether a frame is dropped.
  double get worstMs => math.max(buildMs, rasterMs);
}

/// Summary of the frames of one scenario against one vsync budget.
final class FrameStats {
  const FrameStats._({
    required this.frames,
    required this.budgetMs,
    required this.overBudgetFrames,
    required this.severeFrames,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.rasterP99Ms,
    required this.rasterMaxMs,
    required this.buildP99Ms,
    required this.buildMaxMs,
  });

  /// Summarises [samples]; empty input gives all-zero stats.
  ///
  /// A frame is over budget when its build or raster time exceeds [budgetMs]
  /// (the definition behind the "21 of 455" baseline), severe when it exceeds
  /// twice that.
  factory FrameStats.of(List<FrameSample> samples, {required double budgetMs}) {
    if (samples.isEmpty) {
      return FrameStats._(
        frames: 0,
        budgetMs: budgetMs,
        overBudgetFrames: 0,
        severeFrames: 0,
        rasterP50Ms: 0,
        rasterP90Ms: 0,
        rasterP99Ms: 0,
        rasterMaxMs: 0,
        buildP99Ms: 0,
        buildMaxMs: 0,
      );
    }
    final raster = [for (final s in samples) s.rasterMs];
    final build = [for (final s in samples) s.buildMs];
    return FrameStats._(
      frames: samples.length,
      budgetMs: budgetMs,
      overBudgetFrames: samples.where((s) => s.worstMs > budgetMs).length,
      severeFrames: samples.where((s) => s.worstMs > budgetMs * 2).length,
      rasterP50Ms: percentile(raster, 0.5),
      rasterP90Ms: percentile(raster, 0.9),
      rasterP99Ms: percentile(raster, 0.99),
      rasterMaxMs: raster.reduce(math.max),
      buildP99Ms: percentile(build, 0.99),
      buildMaxMs: build.reduce(math.max),
    );
  }

  final int frames;
  final double budgetMs;
  final int overBudgetFrames;
  final int severeFrames;
  final double rasterP50Ms;
  final double rasterP90Ms;
  final double rasterP99Ms;
  final double rasterMaxMs;
  final double buildP99Ms;
  final double buildMaxMs;
}
