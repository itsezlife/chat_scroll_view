import 'package:workspace_check/src/library_file.dart';
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Keeps platform forks behind one kind of boundary: an
/// `environment_specific/` directory.
///
/// A package that runs on the VM and on the web forks where the two differ (a
/// file system on one, `fetch` on the other). Spread as conditions or as
/// platform imports through ordinary files, the fork is invisible until a web
/// build breaks or a VM-only library reaches it. Held to one directory, every
/// fork reads the same way: a hub file conditionally exports a `_vm` and a
/// `_js` file, each defining the `$entries` the owning type's static calls. Two
/// things are reported in a member's `lib/`, outside such a directory:
///
/// - **A conditional directive** (`if (dart.library.x)`), once per directive,
///   naming its first condition.
/// - **An import or export of a platform library**: `dart:io`, `dart:ffi`,
///   `dart:html`, `dart:js`, `dart:js_interop`, `dart:js_interop_unsafe`,
///   `dart:js_util`, or `package:web`.
///
/// The workspace's own command-line tool ([vmOnly]) runs only on the VM and
/// is not held to it.
abstract final class PlatformForkLint {
  /// Members that only ever run on the VM.
  static const Set<String> vmOnly = <String>{'workspace_check'};

  /// The directory name that marks the boundary.
  static const String boundary = 'environment_specific';

  static final RegExp _platformLibrary = RegExp(
    r'^(dart:(io|ffi|html|js|js_interop|js_interop_unsafe|js_util)$'
    '|package:web/)',
  );

  /// Breaches per member in member order, per file in path order, per
  /// directive in source order.
  static List<Violation> check(WorkspaceGraph graph) => <Violation>[
    for (final member in graph.members)
      if (!vmOnly.contains(member.name))
        for (final file in LibraryFile.allIn(graph, member))
          if (!file.libPath.split('/').contains(boundary))
            for (final directive in file.directives) ...[
              if (directive.condition case final condition?)
                Violation(
                  LintRule.platformForkOutsideBoundary,
                  '${file.repoPath} forks on $condition',
                ),
              for (final uri in directive.uris)
                if (_platformLibrary.hasMatch(uri))
                  Violation(
                    LintRule.platformForkOutsideBoundary,
                    '${file.repoPath} imports $uri',
                  ),
            ],
  ];
}
