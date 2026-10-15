/// Report format and on-disk layout for the panel acceptance test.
///
/// Pure Dart plus `dart:io`, so the on-device test can build reports, the
/// host-side driver can write them, and the runner can read them back.
///
/// Layout under the store root:
///
/// ```text
/// runs/<label>/<scenario>.json   one launch; git-ignored, replaced freely
/// baseline/<scenario>.json       the one kept set for comparison; committed
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'acceptance.dart';
import 'frame_metrics.dart';

/// Everything recorded about one scenario of one launch.
final class ScenarioReport {
  const ScenarioReport({
    required this.scenario,
    required this.asserted,
    required this.meta,
    required this.samples,
    required this.stats,
    required this.verdict,
    this.coverage,
  });

  final String scenario;

  /// Whether the verdict decides the run. Diagnostic scenarios are reported
  /// but never fail it.
  final bool asserted;

  /// Device, mode and display facts that make the numbers interpretable.
  final Map<String, Object?> meta;

  final List<FrameSample> samples;
  final FrameStats stats;
  final Verdict verdict;
  final FlingCoverage? coverage;

  Map<String, Object?> toJson() {
    List<double> series(double Function(FrameSample) pick) => [
      for (final s in samples) double.parse(pick(s).toStringAsFixed(3)),
    ];
    return {
      'scenario': scenario,
      'asserted': asserted,
      'meta': meta,
      'verdict': {'passed': verdict.passed, 'failures': verdict.failures},
      'summary': {
        'frames': stats.frames,
        'budgetMs': stats.budgetMs,
        'overBudgetFrames': stats.overBudgetFrames,
        'severeFrames': stats.severeFrames,
        'buildMs': {'p99': stats.buildP99Ms, 'max': stats.buildMaxMs},
        'rasterMs': {
          'p50': stats.rasterP50Ms,
          'p90': stats.rasterP90Ms,
          'p99': stats.rasterP99Ms,
          'max': stats.rasterMaxMs,
        },
      },
      'coverage': coverage?.toJson(),
      // Per-frame series in delivery order, to line up with a timeline.
      'frames': {
        'buildMs': series((s) => s.buildMs),
        'rasterMs': series((s) => s.rasterMs),
        'totalMs': series((s) => s.totalMs),
      },
    };
  }
}

/// The headline numbers of a stored [ScenarioReport], without the series.
final class ReportSummary {
  const ReportSummary({
    required this.scenario,
    required this.asserted,
    required this.passed,
    required this.frames,
    required this.overBudgetFrames,
    required this.rasterP99Ms,
    required this.rasterMaxMs,
  });

  /// Reads the json written by [ScenarioReport.toJson].
  factory ReportSummary.fromJson(Map<String, Object?> json) {
    final summary = json['summary']! as Map<String, Object?>;
    final raster = summary['rasterMs']! as Map<String, Object?>;
    final verdict = json['verdict']! as Map<String, Object?>;
    return ReportSummary(
      scenario: json['scenario']! as String,
      asserted: json['asserted']! as bool,
      passed: verdict['passed']! as bool,
      frames: (summary['frames']! as num).toInt(),
      overBudgetFrames: (summary['overBudgetFrames']! as num).toInt(),
      rasterP99Ms: (raster['p99']! as num).toDouble(),
      rasterMaxMs: (raster['max']! as num).toDouble(),
    );
  }

  final String scenario;
  final bool asserted;
  final bool passed;
  final int frames;
  final int overBudgetFrames;
  final double rasterP99Ms;
  final double rasterMaxMs;

  /// One line for a console table.
  String describe() =>
      '${scenario.padRight(18)} ${passed ? 'PASS' : 'FAIL'}'
      '${asserted ? '' : ' (info)'} '
      '$overBudgetFrames/$frames frames over budget, '
      'raster p99 ${rasterP99Ms.toStringAsFixed(2)} ms, '
      'max ${rasterMaxMs.toStringAsFixed(1)} ms';
}

/// Whether a launch passed: every asserted scenario is present and passed.
///
/// A launch that crashed before reporting has no summaries and so cannot pass.
bool runPassed(List<ReportSummary> run) {
  for (final name in kAssertedScenarios) {
    final found = run.where((s) => s.scenario == name);
    if (found.isEmpty || !found.every((s) => s.passed)) return false;
  }
  return run.where((s) => s.asserted).every((s) => s.passed);
}

/// Reads and writes reports below one root directory.
final class ReportStore {
  ReportStore(this.root);

  final String root;

  Directory _run(String label) => Directory('$root/runs/$label');
  Directory get _baseline => Directory('$root/baseline');

  /// Writes [report] as `runs/<label>/<scenario>.json`.
  void write(String label, ScenarioReport report) =>
      writeJson(label, report.scenario, report.toJson());

  /// Writes already-encoded report [json] as `runs/<label>/<key>.json`; the
  /// host-side driver receives reports from the device in this form.
  void writeJson(String label, String key, Map<String, Object?> json) {
    final dir = _run(label)..createSync(recursive: true);
    File(
      '${dir.path}/$key.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// Summaries of every scenario report in run [label], sorted by name.
  /// An unknown run is empty.
  List<ReportSummary> readRun(String label) => _read(_run(label));

  /// Summaries of the kept baseline set; empty when none was promoted.
  List<ReportSummary> readBaseline() => _read(_baseline);

  /// Replaces the baseline set with the reports of run [label].
  ///
  /// Throws [StateError] when the run has no reports, so a typo cannot wipe
  /// the baseline.
  void promoteBaseline(String label) {
    final source = _run(label);
    final files = _reportFiles(source);
    if (files.isEmpty) {
      throw StateError('run "$label" has no reports to promote');
    }
    if (_baseline.existsSync()) _baseline.deleteSync(recursive: true);
    _baseline.createSync(recursive: true);
    for (final file in files) {
      file.copySync('${_baseline.path}/${file.uri.pathSegments.last}');
    }
  }

  List<File> _reportFiles(Directory dir) {
    if (!dir.existsSync()) return const [];
    return [
      for (final entity in dir.listSync())
        if (entity is File && _isScenarioReport(entity)) entity,
    ];
  }

  // The driver also drops timeline files next to the reports; only scenario
  // reports carry a `scenario` key.
  bool _isScenarioReport(File file) {
    if (!file.path.endsWith('.json')) return false;
    try {
      final json = jsonDecode(file.readAsStringSync());
      return json is Map<String, Object?> && json.containsKey('scenario');
    } on FormatException {
      return false;
    }
  }

  List<ReportSummary> _read(Directory dir) => [
    for (final file in _reportFiles(dir))
      ReportSummary.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      ),
  ]..sort((a, b) => a.scenario.compareTo(b.scenario));
}
