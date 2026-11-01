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

/// Which way a metric regresses.
enum MetricDirection {
  /// A higher value is the regression (times, shares, counts).
  lowerIsBetter,

  /// A lower value is the regression (a delivery share).
  higherIsBetter,
}

/// Which launch a metric comes from (spec 8, 9).
enum MetricPass {
  /// A timing launch: frame times and scenario outcomes.
  timing,

  /// The traced launch: structural counts from its timeline, never timing.
  traced,
}

/// One named number with its kind, role, direction and pass.
final class Metric {
  const Metric(
    this.value, {
    required this.kind,
    required this.role,
    this.direction = MetricDirection.lowerIsBetter,
    this.pass = MetricPass.timing,
  });

  /// The metric [name] as a document stores it (see [metricTypingOf]).
  factory Metric.fromJson(String name, Map<String, Object?> json) {
    final typing = metricTypingOf(name, json);
    return Metric(
      (json['value']! as num).toDouble(),
      kind: MetricKind.values.byName(json['kind']! as String),
      role: MetricRole.values.byName(json['role']! as String),
      direction: typing.direction,
      pass: typing.pass,
    );
  }

  final double value;
  final MetricKind kind;
  final MetricRole role;
  final MetricDirection direction;
  final MetricPass pass;

  Map<String, Object?> toJson() => {
    'value': value,
    'kind': kind.name,
    'role': role.name,
    'direction': direction.name,
    'pass': pass.name,
  };
}

/// A metric's direction and pass.
typedef MetricTyping = ({MetricDirection direction, MetricPass pass});

/// The typing a stored metric [name] carries in [json].
///
/// A document written before the typing was stored falls back to the rule it
/// relied on then: a `*delivery` metric is higher-is-better, a `trace.*`
/// metric is a count of the traced pass. This is the only place a metric's
/// name decides its typing.
MetricTyping metricTypingOf(String name, Map<String, Object?> json) => (
  direction: switch (json['direction']) {
    final String d => MetricDirection.values.byName(d),
    _ =>
      name.endsWith('delivery')
          ? MetricDirection.higherIsBetter
          : MetricDirection.lowerIsBetter,
  },
  pass: switch (json['pass']) {
    final String p => MetricPass.values.byName(p),
    _ => name.startsWith('trace.') ? MetricPass.traced : MetricPass.timing,
  },
);

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

/// Frames of [samples] whose build or raster took more than three vsync
/// budgets: the one-off outliers a p99 over a long window hides (finding 06).
int framesOverBudgetMultiple(
  List<FrameSample> samples, {
  required double budgetMs,
  double multiple = 3,
}) => samples.where((s) => s.worstMs > budgetMs * multiple).length;

/// Name of the [framesOverBudgetMultiple] diagnostic of every window.
const kFramesOver3xBudgetMetric = 'frames_over_3x_budget';

/// The metrics of one window: the headline set over the [steady] frames, plus
/// `first_frames.*` over the [first] frames. The first frames are diagnostic,
/// or headline when the scenario is [cold]. With no first frames only their
/// zero count is reported, since a percentile of nothing means nothing.
/// [kFramesOver3xBudgetMetric] counts over all the window's frames.
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
        direction: e.value.direction,
      ),
    if (first.isEmpty)
      'first_frames.frames': Metric(0, kind: MetricKind.count, role: role),
    kFramesOver3xBudgetMetric: Metric(
      framesOverBudgetMultiple([
        ...first,
        ...steady,
      ], budgetMs: vsyncBudgetMs(refreshRateHz)).toDouble(),
      kind: MetricKind.count,
      role: MetricRole.diagnostic,
    ),
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
      direction: b.direction,
    );
  }
  return result;
}
