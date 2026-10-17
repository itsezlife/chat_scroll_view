import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:workspace_check/src/library_file.dart';
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Reports a test file that the member's `test/unit_test.dart` does not run.
///
/// `scripts/check` runs one file per member, [entrypoint], which imports every
/// test file and calls its `main` in a group of its own: one compile and one
/// process for the member's whole suite instead of one per file. A test file
/// it does not import would never run in CI, silently, so a member with test
/// files must have the entrypoint and it must import each of them. That the
/// imported `main` is also called is the analyzer's to say: an unused import
/// fails `dart analyze --fatal-infos`.
///
/// Imports are read as text ([DartDirective.scan]), relative to `test/`.
abstract final class TestEntrypointLint {
  /// The member's single test entrypoint, relative to its directory.
  static const String entrypoint = 'test/unit_test.dart';

  /// One violation per member missing its entrypoint, else one per test file
  /// the entrypoint does not import, in member then path order.
  static List<Violation> check(WorkspaceGraph graph) => <Violation>[
    for (final member in graph.members)
      if (member.hasTests) ..._check(graph, member),
  ];

  static Iterable<Violation> _check(
    WorkspaceGraph graph,
    WorkspaceMember member,
  ) sync* {
    String repoPath(String relative) =>
        p.posix.normalize(p.posix.join(member.path, relative));

    final file = File(p.join(graph.directoryOf(member), entrypoint));
    if (!file.existsSync()) {
      yield Violation(
        LintRule.testOutsideEntrypoint,
        '${repoPath(entrypoint)} is missing',
      );
      return;
    }
    final imported = {
      for (final directive in DartDirective.scan(file.readAsStringSync()))
        if (directive.kind == DirectiveKind.import)
          for (final uri in directive.uris) p.posix.normalize(uri),
    };
    final name = p.posix.basename(entrypoint);
    for (final test in member.testFiles) {
      if (test == name || imported.contains(test)) continue;
      yield Violation(
        LintRule.testOutsideEntrypoint,
        '${repoPath('test/$test')} is not run by $entrypoint',
      );
    }
  }
}
