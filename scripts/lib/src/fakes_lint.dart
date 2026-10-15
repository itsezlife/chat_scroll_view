import 'package:path/path.dart' as p;
import 'package:workspace_check/src/library_file.dart';
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Keeps fakes out of production code.
///
/// A **fake source** is a `lib/` file that implements test doubles. The lint
/// recognises one by convention, because nothing else marks it:
///
/// - `lib/testing.dart`, the package's **testing entry point**;
/// - any file under a directory named `testing` or `fakes`;
/// - any file named `fake_*.dart` or `*_fake.dart`.
///
/// **Testing code** is the set of fake sources: it is where fakes live, so it
/// may import them and other packages' `testing.dart` freely (a fake store that
/// extends a model package's fake is the intended shape). Every other file
/// under `lib/` is **production code**, and two rules apply to it:
///
/// - It may not **export** a fake source of its own package. The only public
///   door to fakes is `lib/testing.dart`, so hosts opt in by importing
///   `package:x/testing.dart` and the production barrel never ships them.
/// - It may not **import** a fake source of its own package, nor any other
///   workspace package's fake source (in practice its `testing.dart`).
///
/// Exports of another package's API are [ReexportLint]'s business and are not
/// reported twice. Only `lib/` is scanned: `test/`, `tool/` and the like are
/// exactly where fakes belong.
abstract final class FakesLint {
  static const Set<String> _fakeDirectories = <String>{'testing', 'fakes'};

  static final RegExp _fakeFileName = RegExp(r'^(fake_.+|.+_fake)\.dart$');

  static final RegExp _packageUri = RegExp(r'^package:([^/]+)/(.*)$');

  /// One violation per offending directive, in file then source order.
  static List<Violation> check(WorkspaceGraph graph) {
    final workspacePackages = graph.memberNames;
    return <Violation>[
      for (final member in graph.members)
        for (final file in LibraryFile.allIn(graph, member))
          if (!_isFakeSource(file.libPath))
            for (final directive in file.directives)
              for (final uri in directive.uris)
                ?_violation(
                  directive.kind,
                  uri,
                  file,
                  member.name,
                  workspacePackages,
                ),
    ];
  }

  static Violation? _violation(
    DirectiveKind kind,
    String uri,
    LibraryFile file,
    String ownPackage,
    Set<String> workspacePackages,
  ) {
    final target = _resolve(uri, file, ownPackage);
    if (target == null ||
        !workspacePackages.contains(target.package) ||
        !_isFakeSource(target.libPath)) {
      return null;
    }
    return switch (kind) {
      DirectiveKind.export when target.package == ownPackage => Violation(
        LintRule.fakeExportedOutsideTesting,
        '${file.repoPath} exports $uri',
      ),
      // Another package's API is ReexportLint's to report.
      DirectiveKind.export => null,
      DirectiveKind.import => Violation(
        LintRule.fakeImportedByProduction,
        '${file.repoPath} imports $uri',
      ),
    };
  }

  static bool _isFakeSource(String libPath) {
    final segments = p.posix.split(libPath);
    return libPath == 'testing.dart' ||
        _fakeFileName.hasMatch(segments.last) ||
        segments.take(segments.length - 1).any(_fakeDirectories.contains);
  }

  /// The package and `lib/`-relative path [uri] names when it points into a
  /// package's `lib/`, resolved from [from] (which belongs to [ownPackage]);
  /// null for `dart:` URIs and relative paths that leave `lib/`.
  static ({String package, String libPath})? _resolve(
    String uri,
    LibraryFile from,
    String ownPackage,
  ) {
    if (_packageUri.firstMatch(uri) case final match?) {
      return (package: match.group(1)!, libPath: match.group(2)!);
    }
    if (uri.contains(':')) return null;

    final resolved = p.posix.normalize(
      p.posix.join(p.posix.dirname(from.libPath), uri),
    );
    return resolved.startsWith('..')
        ? null
        : (package: ownPackage, libPath: resolved);
  }
}
