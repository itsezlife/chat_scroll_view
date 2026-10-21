/// The machine-readable side of the asset-cache benchmark: the ratios, counts
/// and rates the nightly job compares against stored baselines.
///
/// Off unless `BENCH_REPORT` names a file, so a plain `flutter test` (the
/// required gate) writes nothing. The json form is read by `workspace_check`
/// (`BenchReport`, in scripts/); this is its producing half, a few lines kept
/// here so the benchmark has no dependency on the tooling that reads it. The
/// schema version below must match `BenchReport.schemaVersion`. The same
/// producer exists in panel_catalog's benchmark: two packages, one small
/// writer each, not a shared package for thirty lines.
library;

import 'dart:convert';
import 'dart:io';

/// Collects named metrics and writes them to the file `BENCH_REPORT` names.
final class RatioReport {
  /// Creates a report for the suite `BENCH_SUITE` names, else [fallbackSuite].
  RatioReport(String fallbackSuite)
    : suite = Platform.environment['BENCH_SUITE'] ?? fallbackSuite;

  /// The suite id the metrics are filed under.
  final String suite;

  final Map<String, Map<String, Object>> _metrics = {};

  /// Metrics recorded so far, by name.
  Iterable<String> get keys => _metrics.keys;

  /// A time over a time measured in the same process; lower is better.
  void ratio(String key, double numeratorUs, double denominatorUs) {
    final base = denominatorUs <= 0 ? 1e-3 : denominatorUs;
    _metrics[key] = {
      'kind': 'ratio',
      'value': double.parse((numeratorUs / base).toStringAsFixed(4)),
    };
  }

  /// An exact count (or a per-event average of one); lower is better.
  void count(String key, num value) {
    _metrics[key] = {
      'kind': 'count',
      'value': double.parse(value.toStringAsFixed(4)),
    };
  }

  /// A fraction between 0 and 1; higher is better.
  void rate(String key, double value) {
    _metrics[key] = {
      'kind': 'rate',
      'value': double.parse(value.toStringAsFixed(4)),
    };
  }

  /// Writes the report when `BENCH_REPORT` is set; does nothing otherwise.
  void writeIfRequested() {
    final path = Platform.environment['BENCH_REPORT'];
    if (path == null || path.isEmpty) return;
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'schema': 1, 'suite': suite, 'metrics': _metrics})}\n',
      );
  }
}

/// Median wall time of [body] per operation, in microseconds, over [repeats]
/// timed passes after one untimed warm-up pass.
///
/// [body] runs [operations] operations per call. The median of repeats, not
/// one long pass: one scheduling hiccup moves a single stopwatch reading, and
/// the median throws it away.
double medianUsPerOp(
  void Function() body, {
  required int operations,
  int repeats = 7,
}) {
  body();
  final passes = <double>[];
  for (var i = 0; i < repeats; i++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    passes.add(watch.elapsedMicroseconds / operations);
  }
  passes.sort();
  return passes[passes.length ~/ 2];
}
