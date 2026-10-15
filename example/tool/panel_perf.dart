// Three-launch acceptance run for the panel catalog, and baseline handling.
//
//   dart run tool/panel_perf.dart <device-id> <label>   three fresh launches
//   dart run tool/panel_perf.dart --promote <run-label> keep a launch as the
//                                                        comparison baseline
//
// Each launch is `tool/run_panel_perf.sh <device-id> <label>-launchN`, a fresh
// build-install-launch, so the engine's glyph atlas is cold every time. Exits
// 0 only when all three launches pass.
//
// The rule and the report format live in integration_test/panel_perf/ and are
// unit-tested in test/panel_perf/.
import 'dart:io';

import '../integration_test/panel_perf/acceptance_runner.dart';
import '../integration_test/panel_perf/report.dart';

Future<void> main(List<String> args) async {
  final exampleDir = File.fromUri(Platform.script).parent.parent.path;
  final store = ReportStore(
    Platform.environment['PERF_OUT'] ?? '$exampleDir/perf',
  );

  if (args.length == 2 && args.first == '--promote') {
    store.promoteBaseline(args[1]);
    stdout.writeln('baseline set replaced by run ${args[1]}');
    return;
  }
  if (args.length != 2 || args.first.startsWith('-')) {
    stderr.writeln(
      'usage: dart run tool/panel_perf.dart <device-id> <label>\n'
      '       dart run tool/panel_perf.dart --promote <run-label>',
    );
    exitCode = 64;
    return;
  }

  final device = args[0];
  final outcome = await AcceptanceRunner(
    launch: (label) async {
      final process = await Process.start(
        '$exampleDir/tool/run_panel_perf.sh',
        [device, label],
        mode: ProcessStartMode.inheritStdio,
        workingDirectory: exampleDir,
      );
      return process.exitCode;
    },
    readRun: store.readRun,
    readBaseline: store.readBaseline,
    log: stdout.writeln,
  ).run(args[1]);
  exitCode = outcome.passed ? 0 : 1;
}
