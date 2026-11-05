import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Reports a golden test that does not go through `golden_baseline`.
///
/// Golden baselines belong to the CI runner: `useGoldenBaselines` compares
/// them there only and refuses to regenerate them anywhere else. A test file
/// that compares goldens without it, or any test code that installs a
/// comparator of its own, brings back baselines made on one machine and
/// failing on the next.
///
/// Reported per file under a member's `test/`, read as text:
///
/// - `<path> compares goldens without useGoldenBaselines` when it calls
///   `matchesGoldenFile` and never `useGoldenBaselines`;
/// - `<path> installs its own golden comparator` when it assigns
///   `goldenFileComparator` or extends / implements a golden comparator.
///
/// Exempt: `golden_baseline` (it is the one comparator) and `workspace_check`
/// (pure Dart, so no golden test; its tests hold this lint's fixtures).
abstract final class GoldenBaselineLint {
  static const Set<String> _exempt = {'golden_baseline', 'workspace_check'};

  static final RegExp _ownComparator = RegExp(
    r'goldenFileComparator\s*=[^=]|'
    r'(extends|implements)\s+(LocalFileComparator|GoldenFileComparator)\b',
  );

  /// Violations in member then path order.
  static List<Violation> check(WorkspaceGraph graph) => <Violation>[
    for (final member in graph.members)
      if (!_exempt.contains(member.name)) ..._check(graph, member),
  ];

  static Iterable<Violation> _check(
    WorkspaceGraph graph,
    WorkspaceMember member,
  ) sync* {
    final test = Directory(p.join(graph.directoryOf(member), 'test'));
    if (!test.existsSync()) return;
    final files =
        test
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final source = file.readAsStringSync();
      final path = p.posix.normalize(
        p.posix.join(
          member.path,
          p.relative(file.path, from: graph.directoryOf(member)),
        ),
      );
      if (source.contains('matchesGoldenFile(') &&
          !source.contains('useGoldenBaselines(')) {
        yield Violation(
          LintRule.goldenOutsideBaseline,
          '$path compares goldens without useGoldenBaselines',
        );
      }
      if (_ownComparator.hasMatch(source)) {
        yield Violation(
          LintRule.goldenOutsideBaseline,
          '$path installs its own golden comparator',
        );
      }
    }
  }
}
