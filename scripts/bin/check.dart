import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:workspace_check/workspace_check.dart';

/// Runs every gate against the workspace this file lives in: the workspace
/// lints, then analyze / test (and per-member hooks), members side by side and
/// reported in dependency order ([CheckRunner]).
///
/// Every step runs even after one fails, so a single run reports everything
/// that is wrong. Exit code: 0 all green, 1 a gate failed, 2 the repository is
/// not a pub workspace the gates understand (or the arguments are wrong).
///
/// `--jobs N` (`-j N`) runs up to N members at once; the default is one per
/// processor, at most [_defaultJobsCap]. `--jobs 1` runs them one at a time.
///
/// Start it through `scripts/check`, which resolves the workspace first.
Future<void> main(List<String> arguments) async {
  final jobs = _jobsFrom(arguments);
  if (jobs == null) {
    stderr.writeln('usage: scripts/check [--jobs N]');
    exitCode = 2;
    return;
  }

  // scripts/bin/check.dart -> workspace root, independent of the caller's cwd.
  final root = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));

  final WorkspaceGraph graph;
  try {
    graph = WorkspaceGraph.load(root);
  } on WorkspaceException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
    return;
  }

  final failed = <String>[];

  stdout.writeln('==> workspace lints');
  if (!_lint(graph)) failed.add('workspace lints');

  final started = Stopwatch()..start();
  failed.addAll(
    await CheckRunner.run(
      CheckPlan.forWorkspace(graph),
      jobs: jobs,
      // A member's test files are the best cheap guess at how long it takes.
      weightOf: (member) => graph.member(member)?.testFiles.length ?? 0,
      runStep: _run,
      report: (step, outcome) => _report(step, outcome, root),
    ),
  );
  stdout.writeln(
    '\nscripts/check: ${_seconds(started.elapsed)} with up to $jobs member(s) '
    'at once.',
  );

  if (failed.isEmpty) {
    stdout.writeln('\nscripts/check: all gates passed.');
    return;
  }
  stdout
    ..writeln('\nscripts/check: ${failed.length} gate(s) failed:')
    ..writeln(failed.map((label) => '  - $label').join('\n'));
  exitCode = 1;
}

/// Prints the violations of all lints (after the legacy baseline); true when
/// there are none.
bool _lint(WorkspaceGraph graph) {
  final violations = LegacyBaseline.apply(<Violation>[
    ...DependencyLint.check(graph),
    ...ReexportLint.check(graph),
    ...FakesLint.check(graph),
    ...PureDartLint.check(graph),
    ...TestEntrypointLint.check(graph),
  ]);
  if (violations.isEmpty) {
    stdout.writeln('    no violations');
    return true;
  }
  violations.forEach(stdout.writeln);
  stdout.writeln('    ${violations.length} violation(s)');
  return false;
}

// Members run side by side, so a step's output is collected and printed
// whole when it is reported, not streamed into the others'.
Future<StepOutcome> _run(CommandStep step) async {
  final watch = Stopwatch()..start();
  final output = StringBuffer();
  try {
    final process = await Process.start(
      step.executable,
      step.arguments,
      workingDirectory: step.workingDirectory,
    );
    const decoder = Utf8Decoder(allowMalformed: true);
    await Future.wait([
      process.stdout.transform(decoder).forEach(output.write),
      process.stderr.transform(decoder).forEach(output.write),
    ]);
    final code = await process.exitCode;
    return StepOutcome(
      passed: code == 0,
      output: '$output',
      elapsed: watch.elapsed,
    );
  } on ProcessException catch (error) {
    // Typically a tool/check hook that is missing its executable bit.
    return StepOutcome(
      passed: false,
      output: 'could not start: ${error.message}\n',
      elapsed: watch.elapsed,
    );
  }
}

void _report(CommandStep step, StepOutcome outcome, String root) {
  stdout
    ..writeln(
      '\n==> ${step.label}   '
      '${outcome.passed ? 'passed' : 'FAILED'} in ${_seconds(outcome.elapsed)}\n'
      '    \$ ${step.commandLine}   '
      '(in ${p.relative(step.workingDirectory, from: root)})',
    )
    ..write(outcome.output);
}

/// The most members run at once by default: past it, test processes and
/// analyzers mostly wait on each other and on memory.
const int _defaultJobsCap = 8;

int? _jobsFrom(List<String> arguments) {
  if (arguments.isEmpty) {
    return math.min(Platform.numberOfProcessors, _defaultJobsCap);
  }
  final value = switch (arguments) {
    ['--jobs' || '-j', final value] => value,
    [final flag] when flag.startsWith('--jobs=') => flag.substring(7),
    _ => null,
  };
  return switch (int.tryParse(value ?? '')) {
    final jobs? when jobs > 0 => jobs,
    _ => null,
  };
}

String _seconds(Duration elapsed) =>
    '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s';
