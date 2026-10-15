import 'dart:io';

import 'package:path/path.dart' as p;

/// A throwaway pub workspace on disk, so loader and file-scanning lints are
/// exercised against real `pubspec.yaml` and `lib/` trees rather than a mock
/// of them.
///
/// Call [dispose] from `addTearDown`.
final class FixtureWorkspace {
  FixtureWorkspace({String rootName = 'root_package'})
    : _rootName = rootName,
      directory = Directory.systemTemp.createTempSync('workspace_check_') {
    _writeRoot();
  }

  /// Absolute path of the workspace root.
  String get path => directory.path;

  /// The workspace root directory.
  final Directory directory;

  final String _rootName;
  final List<String> _memberPaths = <String>[];

  /// Adds a member package at [at] (default `packages/<name>`).
  ///
  /// [dependencies] / [devDependencies] become path-less hosted constraints
  /// (`any`) except `flutter` / `flutter_test`, which become SDK entries.
  /// [files] maps paths relative to the member to their source text.
  void member(
    String name, {
    String? at,
    List<String> dependencies = const <String>[],
    List<String> devDependencies = const <String>[],
    Map<String, String> files = const <String, String>{},
  }) {
    final relative = at ?? 'packages/$name';
    _memberPaths.add(relative);
    write(
      '$relative/pubspec.yaml',
      _pubspec(name, dependencies, devDependencies, workspaceMember: true),
    );
    files.forEach((file, source) => write('$relative/$file', source));
    _writeRoot();
  }

  /// Writes [source] to [relative] under the workspace root.
  void write(String relative, String source) {
    File(p.join(path, relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
  }

  /// Removes the workspace from disk.
  void dispose() => directory.deleteSync(recursive: true);

  void _writeRoot() {
    final buffer = StringBuffer(_pubspec(_rootName, const [], const []));
    if (_memberPaths.isNotEmpty) {
      buffer.writeln('workspace:');
      for (final member in _memberPaths) {
        buffer.writeln('  - $member');
      }
    }
    write('pubspec.yaml', buffer.toString());
  }

  static String _pubspec(
    String name,
    List<String> dependencies,
    List<String> devDependencies, {
    bool workspaceMember = false,
  }) {
    String block(String title, List<String> names) {
      if (names.isEmpty) return '';
      final lines = names.map(
        (n) => n == 'flutter' || n == 'flutter_test'
            ? '  $n:\n    sdk: flutter'
            : '  $n: any',
      );
      return '$title:\n${lines.join('\n')}\n';
    }

    return 'name: $name\n'
        '${workspaceMember ? 'resolution: workspace\n' : ''}'
        'environment:\n  sdk: ^3.11.0\n'
        '${block('dependencies', dependencies)}'
        '${block('dev_dependencies', devDependencies)}';
  }
}
