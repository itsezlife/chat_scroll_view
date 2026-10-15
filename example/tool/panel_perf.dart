// Three-launch acceptance run for the panel catalog, and baseline handling.
//
//   dart run tool/panel_perf.dart [--suite bare|chat|first_run|all] <device-id> <label>
//                                     three fresh launches per suite
//   dart run tool/panel_perf.dart --promote <run-label>...
//                                     keep launches as the comparison baseline
//
// Suites: `bare` is the panel on a bare scaffold, `chat` is the panel opened
// from the real chat screen over generated messages, `all` runs both (default
// `bare`). With `all`, runs are labelled `<label>-bare` and `<label>-chat`.
//
// Each launch is `tool/run_panel_perf.sh <device-id> <label>-launchN` with the
// suite's test target, a fresh install-and-launch, so the engine's glyph atlas
// is cold every time. Exits 0 only when every launch of every chosen suite
// passes.
//
// The rule and the report format live in integration_test/panel_perf/ and are
// unit-tested in test/panel_perf/.
import 'dart:io';

import '../integration_test/panel_perf/acceptance.dart';
import '../integration_test/panel_perf/acceptance_runner.dart';
import '../integration_test/panel_perf/report.dart';

const _usage =
    'usage: dart run tool/panel_perf.dart [--suite bare|chat|first_run|all] '
    '<device-id> <label>\n'
    '       dart run tool/panel_perf.dart --promote <run-label>...';

Future<void> main(List<String> args) async {
  final exampleDir = File.fromUri(Platform.script).parent.parent.path;
  final store = ReportStore(
    Platform.environment['PERF_OUT'] ?? '$exampleDir/perf',
  );

  if (args.length >= 2 && args.first == '--promote') {
    final labels = args.sublist(1);
    store.promoteBaselineFrom(labels);
    stdout.writeln('baseline set replaced by run(s) ${labels.join(', ')}');
    return;
  }

  var rest = args;
  var suiteName = 'bare';
  if (rest.length >= 2 && rest.first == '--suite') {
    suiteName = rest[1];
    rest = rest.sublist(2);
  }
  final suites = suiteName == 'all' ? kSuites : [suiteNamed(suiteName)];
  if (rest.length != 2 || rest.first.startsWith('-') || suites.contains(null)) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final device = rest[0];
  var allPassed = true;
  for (final suite in suites.cast<AcceptanceSuite>()) {
    final label = suites.length > 1 ? '${rest[1]}-${suite.name}' : rest[1];
    final outcome = await AcceptanceRunner(
      suite: suite,
      launch: (launchLabel) async {
        final process = await Process.start(
          '$exampleDir/tool/run_panel_perf.sh',
          [device, launchLabel],
          environment: {'TARGET': suite.target},
          mode: ProcessStartMode.inheritStdio,
          workingDirectory: exampleDir,
        );
        return process.exitCode;
      },
      readRun: store.readRun,
      readBaseline: store.readBaseline,
      log: stdout.writeln,
    ).run(label);
    allPassed = allPassed && outcome.passed;
  }
  exitCode = allPassed ? 0 : 1;
}
