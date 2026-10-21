// The places that name the Flutter SDK exactly. They move together, in one
// command, because a pin that lags makes `flutter pub get` or CI disagree with
// the vendored sources.

import 'dart:io';

/// One file holding an exact SDK version, found under a repo root.
class SdkPin {
  const SdkPin(this.path, this.pattern);

  /// Path from the repo root.
  final String path;

  /// Matches the line holding the version; group 1 is what precedes it, group
  /// 2 the version, group 3 what follows.
  final Pattern pattern;
}

/// The root of the pins: `packages/composer_editable/pubspec.yaml` is the
/// package's own and the one a re-vendor raises.
final List<SdkPin> sdkPins = [
  SdkPin(
    'packages/composer_editable/pubspec.yaml',
    RegExp(r'^(  flutter: )(\d+\.\d+\.\d+)()$', multiLine: true),
  ),
  SdkPin(
    'pubspec.yaml',
    RegExp(r'^(  flutter: )(\d+\.\d+\.\d+)()$', multiLine: true),
  ),
  SdkPin('.fvmrc', RegExp(r'("flutter":\s*")(\d+\.\d+\.\d+)(")')),
  for (final workflow in const [
    'check.yml',
    'platform-builds.yml',
    'benchmarks.yml',
  ])
    SdkPin(
      '.github/workflows/$workflow',
      RegExp(r'^(\s*flutter-version: )(\d+\.\d+\.\d+)()$', multiLine: true),
    ),
];

/// The version [pin] names under [root], or null when the file or line is
/// missing.
String? readPin(Directory root, SdkPin pin) {
  final file = File('${root.path}/${pin.path}');
  if (!file.existsSync()) return null;
  final match = (pin.pattern as RegExp).firstMatch(file.readAsStringSync());
  return match?[2];
}

/// Every pin under [root] mapped to its version (null where absent).
Map<String, String?> readPins(Directory root) => {
  for (final pin in sdkPins) pin.path: readPin(root, pin),
};

/// Rewrites every pin under [root] to [version]. A pin whose file is absent is
/// skipped; one whose line is missing throws, since a silent skip is a pin
/// that lags.
void writePins(Directory root, String version) {
  for (final pin in sdkPins) {
    final file = File('${root.path}/${pin.path}');
    if (!file.existsSync()) continue;
    final regExp = pin.pattern as RegExp;
    final text = file.readAsStringSync();
    if (!regExp.hasMatch(text)) {
      throw StateError('${pin.path} has no SDK version line to raise.');
    }
    file.writeAsStringSync(
      text.replaceFirstMapped(regExp, (m) => '${m[1]}$version${m[3]}'),
    );
  }
}

/// The repo root above [from]: the nearest ancestor whose `pubspec.yaml`
/// declares a `workspace:`.
Directory findRepoRoot(Directory from) {
  var dir = from.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        RegExp(
          '^workspace:',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('No workspace root above ${from.path}.');
    }
    dir = parent;
  }
}
