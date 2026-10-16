/// Runs the panel acceptance test as three fresh launches and requires all
/// three to pass (spec: "three of three consecutive cold launches").
///
/// The process side (how a launch starts, where reports are read from) is
/// injected so the rule itself is testable without a device.
library;

import 'acceptance.dart';
import 'report.dart';

/// Number of consecutive fresh launches that must all pass.
const int kRequiredLaunches = 3;

/// What the operator must guarantee before the numbers mean anything.
const List<String> kDevicePreconditions = [
  'Reference device: S25-class Android, display fixed at 120 Hz.',
  'Device is cool: let it rest idle until it is no longer warm to the touch.',
  'Device is on a charger, screen on, no other app in the foreground.',
  'Profile build only; debug numbers say nothing about raster cost.',
  'Only the reference device gates; other devices and macOS are non-gating.',
];

/// One launch: what its process returned and what its reports say.
final class LaunchResult {
  const LaunchResult({
    required this.label,
    required this.exitCode,
    required this.reports,
    this.requiredScenarios = kAssertedScenarios,
  });

  final String label;
  final int exitCode;
  final List<ReportSummary> reports;

  /// A launch passes only with a clean exit *and* passing reports for every
  /// asserted scenario, so a harness that exits 0 without measuring fails.
  bool get passed => exitCode == 0 && reportsPassed;

  /// Set by [AcceptanceRunner] from the suite's own asserted scenarios.
  final List<String> requiredScenarios;

  bool get reportsPassed =>
      runPassed(reports, requiredScenarios: requiredScenarios);
}

/// All launches of one acceptance run.
final class AcceptanceOutcome {
  const AcceptanceOutcome(this.launches);

  final List<LaunchResult> launches;

  bool get passed =>
      launches.length == kRequiredLaunches && launches.every((l) => l.passed);

  int get passedCount => launches.where((l) => l.passed).length;
}

final class AcceptanceRunner {
  AcceptanceRunner({
    required this.launch,
    required this.readRun,
    required this.log,
    this.readBaseline,
    this.suite = kBareSuite,
  });

  /// What each launch must report; the bare panel unless told otherwise.
  final AcceptanceSuite suite;

  /// Starts one fresh process under run label `<label>-launchN` and returns
  /// its exit code.
  final Future<int> Function(String label) launch;

  /// Summaries written by the launch with this label.
  final List<ReportSummary> Function(String label) readRun;

  /// The kept baseline, shown for comparison when given.
  final List<ReportSummary> Function()? readBaseline;

  final void Function(String line) log;

  /// Runs every launch even after a failure: a red run is the baseline, and
  /// all three samples are the evidence.
  Future<AcceptanceOutcome> run(String label) async {
    log(
      'Panel catalog acceptance, ${suite.name} suite: '
      '$kRequiredLaunches fresh launches.',
    );
    log('Preconditions (operator responsibility):');
    for (final line in kDevicePreconditions) {
      log('  - $line');
    }

    final results = <LaunchResult>[];
    for (var i = 1; i <= kRequiredLaunches; i++) {
      final launchLabel = '$label-launch$i';
      log('--- launch $i of $kRequiredLaunches ($launchLabel) ---');
      final exitCode = await launch(launchLabel);
      final result = LaunchResult(
        label: launchLabel,
        exitCode: exitCode,
        reports: readRun(launchLabel),
        requiredScenarios: suite.assertedScenarios,
      );
      results.add(result);
      log('launch $i exit code $exitCode');
      if (result.reports.isEmpty) log('  no reports were written');
      for (final summary in result.reports) {
        log('  ${summary.describe()}');
      }
      log('launch $i ${result.passed ? 'passed' : 'FAILED'}');
    }

    final baseline = readBaseline?.call() ?? const [];
    if (baseline.isNotEmpty) {
      log('baseline for comparison:');
      for (final summary in baseline) {
        log('  ${summary.describe()}');
      }
    }

    final outcome = AcceptanceOutcome(results);
    log(
      '${outcome.passedCount} of $kRequiredLaunches launches passed: '
      '${outcome.passed ? 'ACCEPTED' : 'FAILED'}',
    );
    return outcome;
  }
}
