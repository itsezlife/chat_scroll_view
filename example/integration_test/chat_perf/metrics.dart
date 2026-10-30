/// Metric values and the headline arithmetic of the chat performance suite.
///
/// Pure Dart: the on-device test, the host-side runner and the unit tests under
/// `test/chat_perf/` share it. The frame arithmetic itself (budget from the
/// refresh rate, nearest-rank percentile) is the panel suite's
/// `frame_metrics.dart`, reused as is.
library;

import '../panel_perf/frame_metrics.dart';

/// What a metric's number means (spec 6.1).
enum MetricKind {
  /// A fraction of the vsync budget or of frames.
  share,

  /// An exact event or object count.
  count,

  /// A time in milliseconds.
  ms,

  /// A quantity in logical pixels.
  dp,

  /// Must equal the baseline.
  exact,

  /// One measured quantity over another from the same launch.
  ratio,
}

/// How a metric is used (spec 6.1): judged, shown, or compared to a goal.
enum MetricRole { headline, diagnostic, target }

/// One named number with its kind and role.
final class Metric {
  const Metric(this.value, {required this.kind, required this.role});

  factory Metric.fromJson(Map<String, Object?> json) => Metric(
    (json['value']! as num).toDouble(),
    kind: MetricKind.values.byName(json['kind']! as String),
    role: MetricRole.values.byName(json['role']! as String),
  );

  final double value;
  final MetricKind kind;
  final MetricRole role;

  Map<String, Object?> toJson() => {
    'value': value,
    'kind': kind.name,
    'role': role.name,
  };
}

/// [timeMs] as a fraction of one vsync [budgetMs]; above one is over budget.
double budgetShare(double timeMs, double budgetMs) => timeMs / budgetMs;

/// The headline set for one window (spec 6.2) from its frames.
///
/// Build and raster p99 as budget shares, the over-budget frame share and the
/// frame count, plus the budget used as a diagnostic. The budget comes from
/// [refreshRateHz] as reported, never from a fixed 16 ms.
Map<String, Metric> headlineMetrics(
  List<FrameSample> samples, {
  required double refreshRateHz,
}) {
  final budgetMs = vsyncBudgetMs(refreshRateHz);
  final stats = FrameStats.of(samples, budgetMs: budgetMs);
  const headline = MetricRole.headline;
  return {
    'build_p99_share': Metric(
      budgetShare(stats.buildP99Ms, budgetMs),
      kind: MetricKind.share,
      role: headline,
    ),
    'raster_p99_share': Metric(
      budgetShare(stats.rasterP99Ms, budgetMs),
      kind: MetricKind.share,
      role: headline,
    ),
    'over_budget_share': Metric(
      stats.frames == 0 ? 0 : stats.overBudgetFrames / stats.frames,
      kind: MetricKind.share,
      role: headline,
    ),
    'frames': Metric(
      stats.frames.toDouble(),
      kind: MetricKind.count,
      role: headline,
    ),
    'budget_ms': Metric(
      budgetMs,
      kind: MetricKind.ms,
      role: MetricRole.diagnostic,
    ),
  };
}
