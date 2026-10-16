import 'package:workspace_check/src/library_file.dart';
import 'package:workspace_check/src/platform_fork_lint.dart';
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Keeps library scope to the units a package means to export: types.
///
/// A public top-level function, getter, setter or variable is in the scope of
/// every file that imports its library, with no type to say whose it is. The
/// operations and constants a package needs live on the types they serve, a
/// pure protocol with no natural host in a named `abstract final class`, and
/// glue stays `_`-private, which is not pollution. The one library-visible
/// name by design is a platform fork's `$entry`, in a file under
/// [PlatformForkLint.boundary].
///
/// Reported once per name, per member in member order, per file in path
/// order, per declaration in source order. The example app is a demo host
/// with its own cleanup and the workspace's command-line tool is not a
/// library ([PlatformForkLint.vmOnly]); neither is held to it.
///
/// Text-based like the other lints. `dart format` starts every top-level
/// declaration at column 0 and indents everything inside one, so a
/// declaration is a column-0 line that is not a directive, an annotation, a
/// comment, a closing bracket or a type declaration (class, enum, mixin,
/// extension, typedef); lines inside block comments and multi-line strings
/// are skipped. The name is the last identifier before the declaration's
/// first `(`, `=`, `;` or `{`, once type arguments and function types are
/// taken out; a function type wrapped over lines leaves its name to the
/// column-0 line after it.
abstract final class LibraryScopeLint {
  /// Member directories not held to the rule.
  static const Set<String> exemptPaths = <String>{'example'};

  static final RegExp _notADeclaration = RegExp(
    r'^(import|export|part|library)\b|^(//|/\*|\*|@|[})\](;])|^\s|^$',
  );
  static final RegExp _typeDeclaration = RegExp(
    r'^((abstract|sealed|base|interface|final|mixin)\s+)*class\b'
    r'|^(enum|mixin|extension|typedef)\b',
  );
  static final RegExp _typeArguments = RegExp('<[^<>]*>');
  static final RegExp _functionType = RegExp(r'\bFunction\??\s*\([^()]*\)\??');
  static final RegExp _modifiers = RegExp(
    r'^(external|static|late|final|const|var)\s+',
  );
  static final RegExp _lastIdentifier = RegExp(r'([A-Za-z_$][\w$]*)\s*$');
  static final RegExp _tripleQuote = RegExp('\'\'\'|"""');

  /// Breaches in the order described above.
  static List<Violation> check(WorkspaceGraph graph) => <Violation>[
    for (final member in graph.members)
      if (!exemptPaths.contains(member.path) &&
          !PlatformForkLint.vmOnly.contains(member.name))
        for (final file in LibraryFile.allIn(graph, member))
          for (final name in declaredNames(file.source))
            if (_isPublic(name, file))
              Violation(
                LintRule.publicLibraryScope,
                '${file.repoPath} declares $name',
              ),
  ];

  /// The names of the top-level functions, accessors and variables [source]
  /// declares, in order (a getter and its setter each count).
  static List<String> declaredNames(String source) {
    final names = <String>[];
    var inComment = false;
    String? inString;
    for (final line in source.split('\n')) {
      if (inComment) {
        inComment = !line.contains('*/');
        continue;
      }
      if (inString case final delimiter?) {
        if (delimiter.allMatches(line).length.isOdd) inString = null;
        continue;
      }
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) continue;
      if (trimmed.startsWith('/*') && !trimmed.contains('*/')) {
        inComment = true;
        continue;
      }
      final opening = _tripleQuote.firstMatch(line)?.group(0);
      final declaration = _nameOf(line);
      if (declaration != null) names.add(declaration);
      if (opening != null && opening.allMatches(line).length.isOdd) {
        inString = opening;
      }
    }
    return names;
  }

  static String? _nameOf(String line) {
    if (_notADeclaration.hasMatch(line) || _typeDeclaration.hasMatch(line)) {
      return null;
    }
    var head = line;
    while (_typeArguments.hasMatch(head)) {
      head = head.replaceAll(_typeArguments, '');
    }
    head = head.replaceAll(_functionType, '');
    while (_modifiers.hasMatch(head)) {
      head = head.replaceFirst(_modifiers, '');
    }
    final end = head.indexOf(RegExp('[(=;{]'));
    if (end <= 0) return null;
    return switch (_lastIdentifier
        .firstMatch(head.substring(0, end))
        ?.group(1)) {
      // A function type wrapped over lines: the name is on the column-0 line
      // that closes it, read in its turn.
      'Function' => null,
      final name => name,
    };
  }

  static bool _isPublic(String name, LibraryFile file) {
    if (name.startsWith('_')) return false;
    final inBoundary = file.libPath
        .split('/')
        .contains(PlatformForkLint.boundary);
    return !(name.startsWith(r'$') && inBoundary);
  }
}
