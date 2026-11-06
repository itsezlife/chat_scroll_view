import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `dart` executable of the SDK running the tests, or null when none can
/// be found. `flutter test` runs under `flutter_tester`, so the Flutter SDK's
/// own Dart is looked up from `FLUTTER_ROOT`, then from `PATH`.
String _join(List<String> parts) => parts.join(Platform.pathSeparator);

String? _findDart() {
  final exe = Platform.isWindows ? 'dart.bat' : 'dart';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final candidate = File(_join([flutterRoot, 'bin', exe]));
    if (candidate.existsSync()) return candidate.path;
  }
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    final candidate = File(_join([dir, exe]));
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

void main() {
  test('the barrel compiles for the web', () async {
    final dart = _findDart();
    if (dart == null) {
      markTestSkipped('no dart executable found (FLUTTER_ROOT, PATH)');
      return;
    }
    final out = Directory.systemTemp.createTempSync('lottie_native_web_');
    addTearDown(() => out.deleteSync(recursive: true));

    final result = await Process.run(dart, [
      'compile',
      'js',
      '--output=${_join([out.path, 'web_entry.js'])}',
      'test/web/web_entry.dart',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
