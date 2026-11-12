/// The numbers of the playback benchmark and their comparison with a
/// committed baseline. Report only: nothing here fails a test.
///
/// The same shape as the report `catalog_assets` and `panel_catalog` write
/// (`schema`, `suite`, `metrics` of `kind` and `value`), kept local like their
/// writers: a test file is not importable across packages, and thirty lines
/// are not a package. It adds one kind, `milliseconds`, because this suite
/// reports what a tick costs on this machine as well as ratios, and it is
/// not read by `scripts/bench`.
library;

import 'package:meta/meta.dart';

/// What a metric counts, and how far from the baseline it may drift before
/// the report calls it worse. Lower is better for every kind.
enum MetricKind {
  /// A duration. Noisy on a laptop in debug mode, so the loosest bound; the
  /// same 50% the other benchmarks use (benchmarks/README.md).
  milliseconds(1.5),

  /// An exact count of bytes or pages, so a tight bound.
  count(1.05),

  /// A time over a time measured in the same process.
  ratio(1.5);

  const MetricKind(this.tolerance);

  /// The factor over the baseline above which a value is [Drift.worse]; its
  /// inverse below the baseline is [Drift.better].
  final double tolerance;
}

/// One named number.
@immutable
final class BenchMetric {
  /// Creates a metric.
  const BenchMetric(this.kind, this.value);

  /// What [value] counts.
  final MetricKind kind;

  /// The number, in the unit of [kind].
  final double value;
}

/// How a metric moved against the baseline.
enum Drift {
  /// Within the tolerance.
  same,

  /// Over the tolerance on the high side.
  worse,

  /// Under the tolerance on the low side: the prompt to re-baseline.
  better,

  /// Reported now, absent from the baseline.
  added,

  /// In the baseline, no longer reported: a probe must not leave unnoticed.
  missing,
}

/// A run's metrics by name.
final class BenchReport {
  /// Creates a report of [metrics].
  BenchReport(this.metrics);

  /// Reads the file [toJson] writes.
  factory BenchReport.fromJson(Map<String, Object?> json) {
    final raw = json['metrics']! as Map<String, Object?>;
    return BenchReport({
      for (final entry in raw.entries)
        entry.key: () {
          final metric = entry.value! as Map<String, Object?>;
          return BenchMetric(
            MetricKind.values.byName(metric['kind']! as String),
            (metric['value']! as num).toDouble(),
          );
        }(),
    });
  }

  /// The metrics by name.
  final Map<String, BenchMetric> metrics;

  /// The file's content.
  Map<String, Object?> toJson({String suite = 'lottie_playback'}) => {
    'schema': 1,
    'suite': suite,
    'metrics': {
      for (final entry in metrics.entries)
        entry.key: {
          'kind': entry.value.kind.name,
          'value': double.parse(entry.value.value.toStringAsFixed(4)),
        },
    },
  };

  /// Every metric of either report against [baseline], in name order.
  List<({String key, double? baseline, double? current, Drift drift})>
  compareTo(BenchReport baseline) {
    final keys = {...metrics.keys, ...baseline.metrics.keys}.toList()..sort();
    return [
      for (final key in keys)
        (
          key: key,
          baseline: baseline.metrics[key]?.value,
          current: metrics[key]?.value,
          drift: _drift(metrics[key], baseline.metrics[key]),
        ),
    ];
  }

  static Drift _drift(BenchMetric? current, BenchMetric? baseline) {
    if (baseline == null) return Drift.added;
    if (current == null) return Drift.missing;
    final tolerance = baseline.kind.tolerance;
    if (baseline.value == 0) {
      return current.value == 0 ? Drift.same : Drift.worse;
    }
    final factor = current.value / baseline.value;
    if (factor > tolerance) return Drift.worse;
    if (factor < 1 / tolerance) return Drift.better;
    return Drift.same;
  }
}
