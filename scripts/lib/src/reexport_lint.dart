import 'package:workspace_check/src/library_file.dart';
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Reports every `export` under a member's `lib/` that names another workspace
/// package.
///
/// A package owns exactly its own API: hosts import what they use, and no
/// package is an umbrella over its neighbours. Re-exporting hides who a host
/// really depends on and lets a neighbour's API change leak through a package
/// that never mentions it.
///
/// Only `export package:<member>/...` of a member other than the file's own is
/// reported. Exporting the package's own files (relative or
/// `package:<self>/...`), packages outside the workspace (a git or hosted
/// dependency) and plain `import`s are all fine. Conditional exports are
/// checked on every branch.
abstract final class ReexportLint {
  static final RegExp _packageUri = RegExp('^package:([^/]+)/');

  /// One violation per offending URI, in file then source order.
  static List<Violation> check(WorkspaceGraph graph) {
    final workspacePackages = graph.memberNames;
    return <Violation>[
      for (final member in graph.members)
        for (final file in LibraryFile.allIn(graph, member))
          for (final directive in file.directives)
            if (directive.kind == DirectiveKind.export)
              for (final uri in directive.uris)
                if (_packageUri.firstMatch(uri) case final match?)
                  if (match.group(1) case final package?
                      when package != member.name &&
                          workspacePackages.contains(package))
                    Violation(
                      LintRule.crossPackageReexport,
                      '${file.repoPath} exports $uri',
                    ),
    ];
  }
}
