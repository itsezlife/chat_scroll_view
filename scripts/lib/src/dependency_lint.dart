import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Checks the dependency direction of the workspace graph against the package
/// topology.
///
/// Rules:
///
/// - **No cycles.** Reported once per cycle, as `a -> b -> a` starting from the
///   alphabetically smallest member.
/// - **Leaves stay leaves.** `content_model` and `chrome_foundation` depend on
///   no workspace package.
/// - **Panel hosts stay payload-free.** `panel_shell`, `panel_pages` and
///   `panel_presentation` never depend on `emoji_catalog_pack` or on a codec /
///   decoder / fetcher adapter package, directly or through other members
///   (reported as the path, `panel_pages -> helper -> emoji_catalog_pack`).
/// - **`panel_catalog` does not see the chrome foundation.** Pages adapt
///   tokens to it, so it never depends on `chrome_foundation`, directly or
///   transitively.
///
/// Adapter packages are recognised by name, since nothing else marks them: a
/// package is an adapter when a `_`-delimited word of its name is `codec`,
/// `decoder` or `fetcher` (or the plural): `lottie_codec`, `disk_fetchers`. An
/// adapter package named otherwise is invisible to this rule.
///
/// Rules naming a package that is not in the workspace yet are inert, so the
/// lint is safe to run on the tree before those packages land.
abstract final class DependencyLint {
  static const Set<String> _leaves = <String>{
    'content_model',
    'chrome_foundation',
  };

  static const Set<String> _payloadFreeHosts = <String>{
    'panel_shell',
    'panel_pages',
    'panel_presentation',
  };

  static const Set<String> _payloadPackages = <String>{'emoji_catalog_pack'};

  static final RegExp _adapterPackage = RegExp(
    r'(^|_)(codec|decoder|fetcher)s?(_|$)',
  );

  static const Map<String, Set<String>> _forbiddenEdges = <String, Set<String>>{
    'panel_catalog': <String>{'chrome_foundation'},
  };

  /// All violations in [graph]: cycles first, then leaf breaches, then the
  /// remaining forbidden edges, each group in member order.
  static List<Violation> check(WorkspaceGraph graph) => <Violation>[
    ..._cycles(graph),
    ..._leafBreaches(graph),
    ..._forbiddenBreaches(graph),
  ];

  static Iterable<Violation> _cycles(WorkspaceGraph graph) {
    final found = <String>{};
    final finished = <String>{};
    final path = <String>[];

    void visit(WorkspaceMember member) {
      final at = path.indexOf(member.name);
      if (at >= 0) {
        found.add(_describeCycle(path.sublist(at)));
        return;
      }
      if (finished.contains(member.name)) return;
      path.add(member.name);
      for (final name in graph.dependenciesOf(member)) {
        if (graph.member(name) case final dependency?) visit(dependency);
      }
      path.removeLast();
      finished.add(member.name);
    }

    graph.members.forEach(visit);
    return found.map((cycle) => Violation(LintRule.dependencyCycle, cycle));
  }

  /// Rotates [cycle] to start at its smallest member so the same cycle always
  /// has the same subject, wherever the traversal entered it.
  static String _describeCycle(List<String> cycle) {
    final smallest = cycle.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final start = cycle.indexOf(smallest);
    final rotated = <String>[
      ...cycle.sublist(start),
      ...cycle.sublist(0, start),
    ];
    return <String>[...rotated, rotated.first].join(' -> ');
  }

  static Iterable<Violation> _leafBreaches(WorkspaceGraph graph) => <Violation>[
    for (final member in graph.members)
      if (_leaves.contains(member.name))
        for (final dependency in graph.dependenciesOf(member))
          Violation(
            LintRule.leafDependsOnPackage,
            '${member.name} -> $dependency',
          ),
  ];

  static Iterable<Violation> _forbiddenBreaches(WorkspaceGraph graph) =>
      <Violation>[
        for (final member in graph.members)
          for (final path in _forbiddenPaths(graph, member))
            Violation(LintRule.forbiddenDependency, path.join(' -> ')),
      ];

  /// Shortest dependency path from [member] to each forbidden package it
  /// reaches, directly or through other members (breadth-first, so a direct
  /// edge reports as `a -> b` and a transitive one as `a -> x -> b`).
  static Iterable<List<String>> _forbiddenPaths(
    WorkspaceGraph graph,
    WorkspaceMember member,
  ) {
    final parents = <String, String>{};
    final queue = <String>[member.name];
    final paths = <List<String>>[];
    for (var i = 0; i < queue.length; i++) {
      final current = graph.member(queue[i]);
      if (current == null) continue;
      for (final next in graph.dependenciesOf(current)) {
        if (next == member.name || parents.containsKey(next)) continue;
        parents[next] = queue[i];
        queue.add(next);
        if (_isForbidden(member.name, next)) {
          final path = <String>[next];
          for (var at = parents[next]; at != null; at = parents[at]) {
            path.add(at);
          }
          paths.add(path.reversed.toList());
        }
      }
    }
    return paths;
  }

  static bool _isForbidden(String from, String to) =>
      (_payloadFreeHosts.contains(from) &&
          (_payloadPackages.contains(to) || _adapterPackage.hasMatch(to))) ||
      (_forbiddenEdges[from]?.contains(to) ?? false);
}
