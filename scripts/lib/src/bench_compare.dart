import 'package:meta/meta.dart';
import 'package:workspace_check/src/bench_report.dart';

/// How far a metric may move before it counts as a regression.
///
/// Headless debug timings are noisy even as ratios, so the defaults are wide
/// on purpose: the nightly job is a tripwire for a change in kind (a 2x), not
/// a meter for percent. The numbers and how they were chosen are in
/// `benchmarks/README.md`.
@immutable
final class BenchTolerance {
  /// Creates a tolerance: [ratio] and [count] are relative growth allowed
  /// (0.5 is 50% worse), [rate] an absolute fall allowed (0.02 is two points).
  const BenchTolerance({
    required this.ratio,
    required this.count,
    required this.rate,
  });

  /// The tolerance the nightly job uses: see `benchmarks/README.md` for the
  /// run-to-run spread it was set from.
  static const standard = BenchTolerance(ratio: 0.5, count: 0.05, rate: 0.02);

  /// Relative growth of a [BenchMetricKind.ratio] before it regressed.
  final double ratio;

  /// Relative growth of a [BenchMetricKind.count] before it regressed.
  final double count;

  /// Absolute fall of a [BenchMetricKind.rate] before it regressed.
  final double rate;
}

/// How one metric stands against its baseline.
enum BenchStatus {
  /// Within the tolerance.
  ok,

  /// Better than the baseline by more than the tolerance. A prompt to
  /// re-baseline, never a failure.
  improved,

  /// Worse than the baseline by more than the tolerance.
  regressed,

  /// Not in the baseline: a new probe.
  added,

  /// In the baseline but not reported now: a probe that went away.
  missing,
}

/// One metric of a [BenchComparison].
@immutable
final class BenchFinding {
  /// Creates a finding for [key].
  const BenchFinding({
    required this.key,
    required this.kind,
    required this.status,
    this.baseline,
    this.current,
  });

  /// The metric name.
  final String key;

  /// What the metric measures.
  final BenchMetricKind kind;

  /// How it stands.
  final BenchStatus status;

  /// The baseline value, null when [status] is [BenchStatus.added].
  final double? baseline;

  /// The current value, null when [status] is [BenchStatus.missing].
  final double? current;
}

/// A report set against its stored baseline.
@immutable
final class BenchComparison {
  const BenchComparison._(this.suite, this.findings);

  /// Compares [current] with [baseline] under [tolerance].
  ///
  /// A metric only the baseline has is a regression ([BenchStatus.missing]):
  /// a probe that quietly stops reporting must not leave the watch list.
  factory BenchComparison.compare({
    required BenchReport baseline,
    required BenchReport current,
    required BenchTolerance tolerance,
  }) {
    final keys = {...baseline.metrics.keys, ...current.metrics.keys}.toList()
      ..sort();
    return BenchComparison._(current.suite, [
      for (final key in keys)
        _judge(key, baseline.metrics[key], current.metrics[key], tolerance),
    ]);
  }

  /// The suite compared.
  final String suite;

  /// Every metric, sorted by name.
  final List<BenchFinding> findings;

  /// The findings that should open an issue.
  List<BenchFinding> get regressions => [
    for (final f in findings)
      if (f.status == BenchStatus.regressed || f.status == BenchStatus.missing)
        f,
  ];

  /// Whether anything regressed.
  bool get hasRegression => regressions.isNotEmpty;

  /// A markdown section: the verdict, then regressions, additions and
  /// improvements before the metrics that held.
  String toMarkdown() {
    final count = regressions.length;
    final buf = StringBuffer()
      ..writeln('### `$suite`: ${_plural(count, 'regression')}')
      ..writeln();
    final order = [
      BenchStatus.regressed,
      BenchStatus.missing,
      BenchStatus.added,
      BenchStatus.improved,
      BenchStatus.ok,
    ];
    final sorted = [...findings]
      ..sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status));
    buf
      ..writeln('| Metric | Kind | Baseline | Current | Status |')
      ..writeln('| ------ | ---- | -------: | ------: | ------ |');
    for (final f in sorted) {
      buf.writeln(
        '| `${f.key}` | ${f.kind.name} | ${_fmt(f.baseline)} | '
        '${_fmt(f.current)} | ${f.status.name} |',
      );
    }
    return buf.toString();
  }

  static BenchFinding _judge(
    String key,
    BenchMetric? baseline,
    BenchMetric? current,
    BenchTolerance tolerance,
  ) {
    final kind = (baseline ?? current)!.kind;
    if (baseline == null) {
      return BenchFinding(
        key: key,
        kind: kind,
        status: BenchStatus.added,
        current: current!.value,
      );
    }
    if (current == null) {
      return BenchFinding(
        key: key,
        kind: kind,
        status: BenchStatus.missing,
        baseline: baseline.value,
      );
    }
    final status = switch (kind) {
      BenchMetricKind.rate => _judgeRate(
        baseline.value,
        current.value,
        tolerance.rate,
      ),
      BenchMetricKind.ratio => _judgeRelative(
        baseline.value,
        current.value,
        tolerance.ratio,
      ),
      BenchMetricKind.count => _judgeRelative(
        baseline.value,
        current.value,
        tolerance.count,
      ),
    };
    return BenchFinding(
      key: key,
      kind: kind,
      status: status,
      baseline: baseline.value,
      current: current.value,
    );
  }

  static BenchStatus _judgeRelative(
    double baseline,
    double current,
    double tolerance,
  ) {
    if (current > baseline * (1 + tolerance)) return BenchStatus.regressed;
    if (current < baseline * (1 - tolerance)) return BenchStatus.improved;
    return BenchStatus.ok;
  }

  static BenchStatus _judgeRate(
    double baseline,
    double current,
    double tolerance,
  ) {
    if (current < baseline - tolerance) return BenchStatus.regressed;
    if (current > baseline + tolerance) return BenchStatus.improved;
    return BenchStatus.ok;
  }

  static String _fmt(double? value) => value == null
      ? '-'
      : value == value.roundToDouble() && value.abs() >= 10
      ? value.toStringAsFixed(0)
      : value.abs() < 0.1
      ? value.toStringAsFixed(3)
      : value.toStringAsFixed(2);

  static String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}
