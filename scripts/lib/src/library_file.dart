import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:workspace_check/src/workspace.dart';

/// Whether a [DartDirective] imports or exports.
enum DirectiveKind {
  /// An `import` directive.
  import,

  /// An `export` directive.
  export,
}

/// An `import` or `export` directive and every URI it names.
///
/// A conditional directive (`export 'a.dart' if (dart.library.io) 'b.dart'`)
/// names several URIs and counts as naming all of them: a re-export is a
/// re-export on whichever platform the condition selects.
@immutable
final class DartDirective {
  /// Creates a directive of [kind] naming [uris], conditional on [condition]
  /// when it has one.
  const DartDirective(this.kind, this.uris, {this.condition});

  /// Import or export.
  final DirectiveKind kind;

  /// Every quoted URI in the directive, in source order (the default URI
  /// first, then each configuration URI).
  final List<String> uris;

  /// The first configuration condition (`dart.library.js_interop`), or null
  /// for an unconditional directive.
  final String? condition;

  // The directive must start its line: that is what rules out commented-out
  // directives (`// export ...`, `/// import ...`) without a comment parser.
  // `[^;]*` runs across lines to reach the `;` of a directive wrapped over
  // `show` / `hide` / `if (...)` clauses.
  static final RegExp _directive = RegExp(
    r'''^[ \t]*(import|export)\s+(['"][^;]*);''',
    multiLine: true,
  );
  static final RegExp _quoted = RegExp('''['"]([^'"]+)['"]''');
  static final RegExp _condition = RegExp(r'\bif\s*\(\s*([\w.]+)');

  /// Directives of [source], in order. `part`, `library` and comments are not
  /// directives of interest and are skipped.
  ///
  /// Text-based on purpose: the lints only need the URIs, and `package:analyzer`
  /// would tie this tool to the SDK's analyzer version. The cost is that a
  /// directive-shaped line inside a block comment is read as a directive (a
  /// spurious violation, so it fails loudly), and a directive that does not
  /// start its line (`import 'a.dart'; export 'b.dart';`) is missed, which
  /// `dart format` rules out by giving each directive its own line.
  static List<DartDirective> scan(String source) => <DartDirective>[
    for (final match in _directive.allMatches(source))
      DartDirective(
        switch (match.group(1)) {
          'export' => DirectiveKind.export,
          _ => DirectiveKind.import,
        },
        <String>[
          for (final uri in _quoted.allMatches(match.group(2)!)) uri.group(1)!,
        ],
        condition: _condition.firstMatch(match.group(2)!)?.group(1),
      ),
  ];
}

/// A Dart file under a member's `lib/`, with its directives already read.
@immutable
final class LibraryFile {
  /// Creates a file record.
  const LibraryFile({
    required this.libPath,
    required this.repoPath,
    required this.directives,
    this.source = '',
  });

  /// Reads every `.dart` file under `lib/` of [member], sorted by path.
  static List<LibraryFile> allIn(WorkspaceGraph graph, WorkspaceMember member) {
    final memberDirectory = graph.directoryOf(member);
    final lib = Directory(p.join(memberDirectory, 'lib'));
    if (!lib.existsSync()) return const <LibraryFile>[];

    final files =
        lib
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return <LibraryFile>[
      for (final file in files)
        if (file.readAsStringSync() case final source)
          LibraryFile(
            libPath: p.relative(file.path, from: lib.path),
            repoPath: p.relative(file.path, from: graph.root),
            directives: DartDirective.scan(source),
            source: source,
          ),
    ];
  }

  /// POSIX path relative to the member's `lib/` (`src/data/fake_x.dart`). The
  /// gates run under bash on macOS and Linux, so paths are not normalised for
  /// Windows.
  final String libPath;

  /// Path relative to the workspace root (`packages/x/lib/src/data/fake_x.dart`).
  /// This is what violations print, so it is clickable from the repo root.
  final String repoPath;

  /// Imports and exports of the file.
  final List<DartDirective> directives;

  /// The text of the file.
  final String source;
}
