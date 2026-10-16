import 'package:meta/meta.dart';

/// What a benchmark metric measures, which decides its direction and the
/// tolerance it is judged with ([BenchTolerance]).
enum BenchMetricKind {
  /// A unitless time ratio (candidate over a baseline measured in the same
  /// process). Lower is better; absolute microseconds never get here, so a
  /// slower machine does not move it.
  ratio,

  /// An exact object, node or event count. Lower is better.
  count,

  /// A fraction between 0 and 1, such as a cache hit rate. Higher is better.
  rate;

  /// Whether a larger value is the better one.
  bool get higherIsBetter => this == rate;
}

/// One named, comparable number of a benchmark run.
@immutable
final class BenchMetric {
  /// Creates a metric of [kind] with [value].
  const BenchMetric(this.kind, this.value);

  /// Reads the json form written by [toJson]; throws [FormatException] for an
  /// unknown kind or a value that is not a number.
  factory BenchMetric.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatException('a metric is an object, got $json');
    }
    final kindName = json['kind'];
    final kind = BenchMetricKind.values.where((k) => k.name == kindName);
    final value = json['value'];
    if (kind.isEmpty || value is! num) {
      throw FormatException('not a metric: $json');
    }
    return BenchMetric(kind.single, value.toDouble());
  }

  /// What is measured.
  final BenchMetricKind kind;

  /// The measurement.
  final double value;

  /// The json form read by [BenchMetric.fromJson].
  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};
}

/// The metrics of one benchmark suite from one run, or the median of several
/// runs: what a baseline file stores and what the comparison reads.
///
/// Metrics are keyed by a stable dotted name (`layout.ssl.512`); renaming one
/// reads as a metric that went missing and a new one that appeared.
@immutable
final class BenchReport {
  /// Creates a report of [suite] with [metrics].
  const BenchReport({required this.suite, required this.metrics});

  /// Reads the json form written by [toJson]; throws [FormatException] for a
  /// schema this code does not know.
  factory BenchReport.fromJson(Map<String, Object?> json) {
    if (json['schema'] != schemaVersion) {
      throw FormatException(
        'unknown benchmark report schema ${json['schema']} '
        '(this code reads $schemaVersion)',
      );
    }
    final metrics = json['metrics'];
    final suite = json['suite'];
    if (metrics is! Map<String, Object?> || suite is! String) {
      throw FormatException('not a benchmark report: $json');
    }
    return BenchReport(
      suite: suite,
      metrics: {
        for (final entry in metrics.entries)
          entry.key: BenchMetric.fromJson(entry.value),
      },
    );
  }

  /// The median of every metric over [runs]: one run is noisy, the median of
  /// an odd number of them is a number a run actually produced. Only metrics
  /// every run reported are kept.
  factory BenchReport.medianOf(List<BenchReport> runs) {
    if (runs.isEmpty) {
      throw ArgumentError.value(runs, 'runs', 'needs at least one run');
    }
    final keys = runs
        .map((r) => r.metrics.keys.toSet())
        .reduce((a, b) => a.intersection(b));
    return BenchReport(
      suite: runs.first.suite,
      metrics: {
        for (final key in runs.first.metrics.keys.where(keys.contains))
          key: BenchMetric(
            runs.first.metrics[key]!.kind,
            _median([for (final r in runs) r.metrics[key]!.value]),
          ),
      },
    );
  }

  /// The version of the json form. Bump it when the shape changes, so an old
  /// baseline is refused instead of misread.
  static const int schemaVersion = 1;

  /// The suite these metrics belong to.
  final String suite;

  /// Metrics by name.
  final Map<String, BenchMetric> metrics;

  /// The report made [factor] times worse in every metric: ratios and counts
  /// multiplied, rates divided. Used to prove the alarm path end to end
  /// (`--inject-regression`) without waiting for a real regression.
  BenchReport regressed(double factor) => BenchReport(
    suite: suite,
    metrics: {
      for (final entry in metrics.entries)
        entry.key: BenchMetric(
          entry.value.kind,
          entry.value.kind.higherIsBetter
              ? entry.value.value / factor
              : entry.value.value * factor,
        ),
    },
  );

  /// The json form read by [BenchReport.fromJson], keys sorted so a stored
  /// baseline diffs cleanly.
  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'suite': suite,
    'metrics': {
      for (final key in metrics.keys.toList()..sort())
        key: metrics[key]!.toJson(),
    },
  };

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
