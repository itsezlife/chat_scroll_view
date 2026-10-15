import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown when the directory handed to [WorkspaceGraph.load] is not the pub
/// workspace the gates assume (no `workspace:` list, a listed member without a
/// pubspec, a glob entry).
///
/// The gates fail loudly here instead of checking an empty or partial member
/// set: a lint that scans nothing passes, which is the worst way for it to fail.
final class WorkspaceException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const WorkspaceException(this.message);

  /// What is wrong with the workspace layout, naming the offending path.
  final String message;

  @override
  String toString() => 'WorkspaceException: $message';
}

/// One package of the pub workspace as its `pubspec.yaml` and directory
/// declare it.
///
/// A plain value: the lints and [CheckPlan] decide from these facts and never
/// touch the filesystem for them again, which keeps them testable with
/// in-memory members.
@immutable
final class WorkspaceMember {
  /// Creates a member. The defaults describe a bare pure-Dart package with no
  /// dependencies, tests, or hook.
  const WorkspaceMember({
    required this.name,
    required this.path,
    this.dependencies = const <String>{},
    this.usesFlutter = false,
    this.analysisTargets = const <String>[],
    this.hasTests = false,
    this.hasCheckHook = false,
  });

  /// Directories a pub package keeps Dart code in, in the order they are
  /// analyzed.
  ///
  /// The member is analyzed through these rather than as its whole directory:
  /// the root package contains every other member, and `example/` vendors
  /// plugins under `packages/`, so analyzing the directory would check the
  /// same code once per enclosing member and pull in code this gate does not
  /// own.
  static const List<String> layoutDirectories = <String>[
    'lib',
    'bin',
    'test',
    'tool',
    'benchmark',
    'integration_test',
    'test_driver',
  ];

  /// The `name:` of the package.
  final String name;

  /// Directory of the member relative to the workspace root, `.` for the root
  /// package itself.
  final String path;

  /// Every package named in `dependencies:` or `dev_dependencies:`, workspace
  /// member or not. [WorkspaceGraph.dependenciesOf] narrows it to members.
  final Set<String> dependencies;

  /// Whether any dependency is an SDK entry for Flutter (`flutter`,
  /// `flutter_test`, `integration_test`, ...).
  ///
  /// Selects `flutter test` over `dart test`: the Dart test runner cannot load
  /// `dart:ui`.
  final bool usesFlutter;

  /// Subset of [layoutDirectories] that exist in this member.
  final List<String> analysisTargets;

  /// Whether `test/` holds at least one `*_test.dart`. `dart test` exits
  /// non-zero on a package with no test files, so a member without any is
  /// skipped rather than failed.
  final bool hasTests;

  /// Whether the member ships `tool/check`: a per-member gate (for example the
  /// generator reproducibility check) that [CheckPlan] runs after the member's
  /// tests, from the member directory.
  final bool hasCheckHook;
}

/// The members of a pub workspace and the dependency edges between them.
///
/// Built once per run by [WorkspaceGraph.load] and shared by every lint and by
/// [CheckPlan]. Edges come from the declared `dependencies:` /
/// `dev_dependencies:` names, so a cycle through a dev dependency counts: pub
/// workspaces resolve all members together and such a cycle is as real as one
/// through a runtime dependency.
final class WorkspaceGraph {
  /// Creates a graph over [members] rooted at [root].
  ///
  /// [members] are held sorted by name so every traversal is deterministic.
  WorkspaceGraph({
    required this.root,
    required Iterable<WorkspaceMember> members,
  }) : members = List<WorkspaceMember>.unmodifiable(
         members.toList()..sort((a, b) => a.name.compareTo(b.name)),
       );

  /// Reads the workspace rooted at [root]: the root package plus every path
  /// listed under `workspace:` in the root `pubspec.yaml`.
  ///
  /// `workspace:` entries are read literally. Globs are rejected because the
  /// gates would otherwise have to re-implement pub's matching to know which
  /// members exist.
  ///
  /// Throws a [WorkspaceException] when the layout is not a workspace, or when
  /// a package under `packages/` or `example/` is missing from the list: an
  /// unlisted package would silently escape every lint, analysis and test step.
  factory WorkspaceGraph.load(String root) {
    final rootPubspec = _readPubspec(root);
    final listed = switch (rootPubspec['workspace']) {
      final YamlList entries => entries.map((e) => '$e').toList(),
      _ => throw WorkspaceException(
        '${p.join(root, 'pubspec.yaml')} has no `workspace:` list; '
        'scripts/check must run against the pub workspace root.',
      ),
    };

    final entries = <String>[for (final entry in listed) _checkedEntry(entry)];
    _checkNoneUnlisted(root, entries.toSet());

    final members = <WorkspaceMember>[
      _readMember(root, '.', rootPubspec),
      for (final entry in entries)
        _readMember(root, entry, _readPubspec(p.join(root, entry))),
    ];
    return WorkspaceGraph(root: root, members: members);
  }

  /// Absolute path of the workspace root.
  final String root;

  /// All members, sorted by name.
  final List<WorkspaceMember> members;

  /// The member called [name], or null when the workspace has none.
  WorkspaceMember? member(String name) {
    for (final candidate in members) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  /// Names of all members.
  Set<String> get memberNames => {for (final m in members) m.name};

  /// Names of the workspace members [member] declares a dependency on, sorted.
  ///
  /// Packages outside the workspace and the member itself are not edges.
  Set<String> dependenciesOf(WorkspaceMember member) {
    final names = memberNames;
    return (member.dependencies
            .where((name) => name != member.name && names.contains(name))
            .toList()
          ..sort())
        .toSet();
  }

  /// Members ordered so each comes after everything it depends on.
  ///
  /// Deterministic: members are visited alphabetically and each is preceded by
  /// its own dependencies (depth-first), so the same workspace always yields
  /// the same order.
  ///
  /// Total even on a cyclic graph (each member appears once; the edge that
  /// closes the cycle is ignored), so a cycle surfaces as a lint violation
  /// instead of a crash while the plan is being built.
  List<WorkspaceMember> inDependencyOrder() {
    final ordered = <WorkspaceMember>[];
    final visited = <String>{};
    void visit(WorkspaceMember member) {
      if (!visited.add(member.name)) return;
      for (final name in dependenciesOf(member)) {
        if (this.member(name) case final dependency?) visit(dependency);
      }
      ordered.add(member);
    }

    members.forEach(visit);
    return ordered;
  }

  /// Absolute directory of [member].
  String directoryOf(WorkspaceMember member) =>
      p.normalize(p.join(root, member.path));

  static void _checkNoneUnlisted(String root, Set<String> listed) {
    final packages = Directory(p.join(root, 'packages'));
    final candidates = <String>[
      'example',
      if (packages.existsSync())
        for (final child in packages.listSync().whereType<Directory>())
          p.join('packages', p.basename(child.path)),
    ];
    final unlisted = <String>[
      for (final candidate in candidates)
        if (File(p.join(root, candidate, 'pubspec.yaml')).existsSync() &&
            !listed.contains(candidate))
          candidate,
    ]..sort();
    if (unlisted.isNotEmpty) {
      throw WorkspaceException(
        'Not listed under `workspace:` in pubspec.yaml: '
        '${unlisted.join(', ')}. scripts/check would skip them silently.',
      );
    }
  }

  static String _checkedEntry(String entry) {
    if (entry.contains(RegExp(r'[*?\[\]{}]'))) {
      throw WorkspaceException(
        '`workspace:` entry "$entry" is a glob; list member directories '
        'literally so scripts/check sees the same set pub does.',
      );
    }
    return p.normalize(entry);
  }

  static YamlMap _readPubspec(String directory) {
    final file = File(p.join(directory, 'pubspec.yaml'));
    if (!file.existsSync()) {
      throw WorkspaceException('No pubspec.yaml at ${p.relative(file.path)}.');
    }
    return switch (loadYaml(file.readAsStringSync())) {
      final YamlMap map => map,
      _ => throw WorkspaceException('${file.path} is not a YAML mapping.'),
    };
  }

  static WorkspaceMember _readMember(
    String root,
    String path,
    YamlMap pubspec,
  ) {
    final directory = p.normalize(p.join(root, path));
    final dependencies = <String>{};
    var usesFlutter = false;
    for (final section in const ['dependencies', 'dev_dependencies']) {
      if (pubspec[section] case final YamlMap declared) {
        for (final entry in declared.entries) {
          dependencies.add('${entry.key}');
          if (entry.value case {'sdk': 'flutter'}) usesFlutter = true;
        }
      }
    }

    return WorkspaceMember(
      name: '${pubspec['name']}',
      path: path,
      dependencies: dependencies,
      usesFlutter: usesFlutter,
      analysisTargets: [
        for (final layout in WorkspaceMember.layoutDirectories)
          if (Directory(p.join(directory, layout)).existsSync()) layout,
      ],
      hasTests: _hasTestFiles(p.join(directory, 'test')),
      hasCheckHook: File(p.join(directory, 'tool', 'check')).existsSync(),
    );
  }

  static bool _hasTestFiles(String directory) {
    final tests = Directory(directory);
    return tests.existsSync() &&
        tests
            .listSync(recursive: true)
            .whereType<File>()
            .any((file) => file.path.endsWith('_test.dart'));
  }
}
