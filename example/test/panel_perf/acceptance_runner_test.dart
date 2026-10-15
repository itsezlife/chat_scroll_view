import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/panel_perf/acceptance_runner.dart';
import '../../integration_test/panel_perf/report.dart';

ReportSummary _summary(String scenario, {bool passed = true}) => ReportSummary(
  scenario: scenario,
  asserted: true,
  passed: passed,
  frames: 455,
  overBudgetFrames: passed ? 0 : 21,
  rasterP99Ms: passed ? 1 : 30,
  rasterMaxMs: passed ? 1.5 : 68,
);

List<ReportSummary> _run({bool passed = true}) => [
  _summary('panel_open', passed: passed),
  _summary('cold_first_pass', passed: passed),
];

/// Drives the runner with scripted exit codes and reports per launch label.
final class _Script {
  _Script(this.exitCodes, this.runs);

  final List<int> exitCodes;
  final Map<String, List<ReportSummary>> runs;
  final launched = <String>[];
  final lines = <String>[];

  AcceptanceRunner get runner => AcceptanceRunner(
    launch: (label) async {
      launched.add(label);
      return exitCodes[launched.length - 1];
    },
    readRun: (label) => runs[label] ?? const [],
    log: lines.add,
  );
}

void main() {
  test('three clean launches pass the run', () async {
    final script = _Script(
      [0, 0, 0],
      {for (var i = 1; i <= 3; i++) 's25-launch$i': _run()},
    );
    final outcome = await script.runner.run('s25');

    expect(outcome.passed, isTrue);
    expect(script.launched, ['s25-launch1', 's25-launch2', 's25-launch3']);
  });

  test('one bad launch fails the run but all three still execute', () async {
    final script = _Script(
      [0, 1, 0],
      {
        's25-launch1': _run(),
        's25-launch2': _run(passed: false),
        's25-launch3': _run(),
      },
    );
    final outcome = await script.runner.run('s25');

    expect(outcome.passed, isFalse);
    expect(script.launched, hasLength(3));
    expect(outcome.launches.map((l) => l.passed), [true, false, true]);
  });

  test('a zero exit with no reports is not a pass', () async {
    final script = _Script(
      [0, 0, 0],
      {
        's25-launch1': _run(),
        's25-launch2': _run(),
        // launch 3 produced nothing
      },
    );
    final outcome = await script.runner.run('s25');

    expect(outcome.passed, isFalse);
    expect(outcome.launches.last.passed, isFalse);
  });

  test(
    'a non-zero exit fails a launch even if its reports look clean',
    () async {
      final script = _Script(
        [0, 0, 255],
        {for (var i = 1; i <= 3; i++) 's25-launch$i': _run()},
      );
      expect((await script.runner.run('s25')).passed, isFalse);
    },
  );

  test('the device precondition is printed before the first launch', () async {
    final script = _Script(
      [0, 0, 0],
      {for (var i = 1; i <= 3; i++) 's25-launch$i': _run()},
    );
    await script.runner.run('s25');

    final firstLaunchLine = script.lines.indexWhere(
      (l) => l.contains('launch 1'),
    );
    final before = script.lines.take(firstLaunchLine).join('\n');
    expect(before, contains('cool'));
    expect(before, contains('charger'));
    expect(before, contains('120 Hz'));
  });

  test('the console shows each launch and a final verdict', () async {
    final script = _Script(
      [0, 1, 0],
      {
        's25-launch1': _run(),
        's25-launch2': _run(passed: false),
        's25-launch3': _run(),
      },
    );
    await script.runner.run('s25');

    final out = script.lines.join('\n');
    expect(out, contains('launch 2'));
    expect(out, contains('21/455'));
    expect(out, contains('FAILED'));
  });

  test('a passing run says so', () async {
    final script = _Script(
      [0, 0, 0],
      {for (var i = 1; i <= 3; i++) 's25-launch$i': _run()},
    );
    await script.runner.run('s25');
    expect(script.lines.join('\n'), contains('3 of 3 launches passed'));
  });

  test('baseline numbers are shown for comparison when provided', () async {
    final script = _Script(
      [0, 0, 0],
      {for (var i = 1; i <= 3; i++) 's25-launch$i': _run()},
    );
    final runner = AcceptanceRunner(
      launch: (label) async => 0,
      readRun: (label) => _run(),
      readBaseline: () => _run(passed: false),
      log: script.lines.add,
    );
    await runner.run('s25');
    final out = script.lines.join('\n');
    expect(out, contains('baseline'));
    expect(out, contains('21/455'));
  });
}
