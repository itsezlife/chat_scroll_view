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

/// Default span of a window's first frames, in milliseconds (spec 5).
const double kFirstFramesSpanMs = 150;

/// Splits [items] (frames, in order, with their start times [startsMs] in
/// milliseconds) into those starting within [spanMs] of the first one and the
/// rest.
(List<T>, List<T>) splitFirstFrames<T>(
  List<T> items,
  List<double> startsMs, {
  double spanMs = kFirstFramesSpanMs,
}) {
  assert(items.length == startsMs.length, 'one start time per item');
  if (items.isEmpty) return (<T>[], <T>[]);
  final end = startsMs.first + spanMs;
  var cut = 0;
  while (cut < items.length && startsMs[cut] < end) {
    cut++;
  }
  return (items.sublist(0, cut), items.sublist(cut));
}

/// The metrics of one window: the headline set over the [steady] frames, plus
/// `first_frames.*` over the [first] frames. The first frames are diagnostic,
/// or headline when the scenario is [cold]. With no first frames only their
/// zero count is reported, since a percentile of nothing means nothing.
Map<String, Metric> windowMetrics(
  List<FrameSample> first,
  List<FrameSample> steady, {
  required double refreshRateHz,
  required bool cold,
}) {
  final role = cold ? MetricRole.headline : MetricRole.diagnostic;
  final head = first.isEmpty
      ? <String, Metric>{}
      : (headlineMetrics(first, refreshRateHz: refreshRateHz)
          ..remove('budget_ms'));
  return {
    ...headlineMetrics(steady, refreshRateHz: refreshRateHz),
    for (final e in head.entries)
      'first_frames.${e.key}': Metric(
        e.value.value,
        kind: e.value.kind,
        role: role,
      ),
    if (first.isEmpty)
      'first_frames.frames': Metric(0, kind: MetricKind.count, role: role),
  };
}

/// Each of [names] in [other] divided by the same metric in [base], as a
/// `ratio`. A metric absent from either, or zero in [base], has no ratio.
Map<String, Metric> ratioMetrics({
  required Map<String, Metric> base,
  required Map<String, Metric> other,
  required Iterable<String> names,
}) {
  final result = <String, Metric>{};
  for (final name in names) {
    final a = base[name];
    final b = other[name];
    if (a == null || b == null || a.value == 0) continue;
    result[name] = Metric(
      b.value / a.value,
      kind: MetricKind.ratio,
      role: MetricRole.diagnostic,
    );
  }
  return result;
}
