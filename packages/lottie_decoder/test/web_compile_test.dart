import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _join(List<String> parts) => parts.join(Platform.pathSeparator);

/// The `dart` executable and the Flutter web SDK's library specification, or
/// null when either cannot be found. `flutter test` runs under
/// `flutter_tester`, so the Flutter SDK is looked up from `FLUTTER_ROOT`,
/// then from `PATH`.
({String dart, String libraries})? _findToolchain() {
  final exe = Platform.isWindows ? 'dart.bat' : 'dart';
  final roots = <String>[];
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) roots.add(flutterRoot);
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isNotEmpty) roots.add(File(_join([dir, exe])).parent.parent.path);
  }
  for (final root in roots) {
    final dart = File(_join([root, 'bin', exe]));
    final libraries = File(
      _join([root, 'bin', 'cache', 'flutter_web_sdk', 'libraries.json']),
    );
    if (dart.existsSync() && libraries.existsSync()) {
      return (dart: dart.path, libraries: libraries.path);
    }
  }
  return null;
}

void main() {
  test(
    'the neutral decode path compiles for the web',
    () async {
      final toolchain = _findToolchain();
      if (toolchain == null) {
        markTestSkipped('no Flutter web SDK found (FLUTTER_ROOT, PATH)');
        return;
      }
      final out = Directory.systemTemp.createTempSync('lottie_decoder_web_');
      addTearDown(() => out.deleteSync(recursive: true));

      // The plain Dart compiler does not know dart:ui; the Flutter web SDK's
      // library specification is what a Flutter web build compiles against.
      final result = await Process.run(toolchain.dart, [
        'compile',
        'js',
        '--libraries-spec=${toolchain.libraries}',
        '--output=${_join([out.path, 'web_entry.js'])}',
        'test/web/web_entry.dart',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
