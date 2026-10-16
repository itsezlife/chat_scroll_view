/// The machine-readable side of the headless benchmark: the ratios and counts
/// the nightly job compares against stored baselines.
///
/// Off unless `BENCH_REPORT` names a file, so a plain `flutter test` (the
/// required gate) prints its tables and writes nothing. The json form is read
/// by `workspace_check` (`BenchReport`, in scripts/); this is its producing
/// half, kept as a few lines here rather than a shared package so the
/// benchmark has no dependency on the tooling that reads it. The schema
/// version below must match `BenchReport.schemaVersion`.
library;

import 'dart:convert';
import 'dart:io';

/// The semantics preset of the benchmark, chosen by `BENCH_SEMANTICS`
/// (`off`, the default, or `on`).
///
/// `flutter_test` turns semantics on for every widget test, which charges
/// every probe for a semantic tree that only exists on a device while a
/// screen reader runs. The shipped default is off, so the headline probes run
/// off and measure what a user without a screen reader pays. The cost of
/// describing the window to a screen reader has its own probe (`semantics on -
/// scroll frames`, always measured against the same frames without), and the
/// nightly job runs the whole suite in both presets so a regression that only
/// a screen reader pays is tracked too.
bool get benchSemanticsEnabled =>
    (Platform.environment['BENCH_SEMANTICS'] ?? 'off') == 'on';

/// Collects named metrics and writes them to the file `BENCH_REPORT` names.
final class RatioReport {
  /// Creates a report for the suite `BENCH_SUITE` names, else [fallbackSuite].
  RatioReport(String fallbackSuite)
    : suite = Platform.environment['BENCH_SUITE'] ?? fallbackSuite;

  /// The suite id the metrics are filed under.
  final String suite;

  final Map<String, Map<String, Object>> _metrics = {};

  /// Candidate over baseline, both medians in the same process; lower is
  /// better. A zero baseline (a sample below the clock's resolution) is read
  /// as one microsecond so a ratio always exists.
  void ratio(String key, double candidateUs, double baselineUs) {
    final base = baselineUs < 1 ? 1.0 : baselineUs;
    _metrics[key] = {
      'kind': 'ratio',
      'value': double.parse((candidateUs / base).toStringAsFixed(4)),
    };
  }

  /// An exact count; lower is better.
  void count(String key, int value) {
    _metrics[key] = {'kind': 'count', 'value': value};
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
