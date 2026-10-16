import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:workspace_check/workspace_check.dart';

/// Runs every gate against the workspace this file lives in: the workspace
/// lints, then analyze / test (and per-member hooks) in dependency order.
///
/// Every step runs even after one fails, so a single run reports everything
/// that is wrong. Exit code: 0 all green, 1 a gate failed, 2 the repository is
/// not a pub workspace the gates understand.
///
/// Start it through `scripts/check`, which resolves the workspace first.
Future<void> main() async {
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

  for (final step in CheckPlan.forWorkspace(graph)) {
    if (!await _run(step, root)) failed.add(step.label);
  }

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
  ]);
  if (violations.isEmpty) {
    stdout.writeln('    no violations');
    return true;
  }
  violations.forEach(stdout.writeln);
  stdout.writeln('    ${violations.length} violation(s)');
  return false;
}

Future<bool> _run(CommandStep step, String root) async {
  stdout.writeln(
    '\n==> ${step.label}\n'
    '    \$ ${step.commandLine}   '
    '(in ${p.relative(step.workingDirectory, from: root)})',
  );
  try {
    final process = await Process.start(
      step.executable,
      step.arguments,
      workingDirectory: step.workingDirectory,
      mode: ProcessStartMode.inheritStdio,
    );
    return await process.exitCode == 0;
  } on ProcessException catch (error) {
    // Typically a tool/check hook that is missing its executable bit.
    stdout.writeln('    could not start: ${error.message}');
    return false;
  }
}
