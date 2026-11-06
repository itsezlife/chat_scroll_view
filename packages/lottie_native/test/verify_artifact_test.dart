import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The tool is not part of lib/: it is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../native/tool/verify_artifact.dart' show runVerifyArtifact;
import 'support/library_headers.dart';

void main() {
  late Directory temp;
  late StringBuffer out;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('verify_artifact');
    out = StringBuffer();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File write(List<int> bytes) =>
      File('${temp.path}/libchat_lottie-x')..writeAsBytesSync(bytes);

  test('prints OK and exits 0 for a sound library', () {
    final file = write(soundLibraryFor('android-arm64'));

    expect(runVerifyArtifact([file.path, 'android-arm64'], out: out), 0);
    expect(out.toString().trim(), 'OK');
  });

  test('exits 1 and prints the problem for the wrong architecture', () {
    final file = write(soundLibraryFor('android-x64'));

    final code = runVerifyArtifact([file.path, 'android-arm64'], out: out);

    expect(code, 1);
    expect(out.toString(), allOf(contains('0x3e'), contains('0xb7')));
  });

  test('exits 1 for 4 KB aligned Android segments', () {
    final file = write(
      elfLibrary(machine: elfAarch64, segments: [(ptLoad, 0x1000)]),
    );

    expect(runVerifyArtifact([file.path, 'android-arm64'], out: out), 1);
    expect(out.toString(), contains('16 KB'));
  });

  test('exits 1 for each key given a header of another format', () {
    final file = write(soundLibraryFor('linux-x64'));
    for (final key in ['macos-arm64', 'windows-x64']) {
      expect(runVerifyArtifact([file.path, key], out: out), 1, reason: key);
    }
  });

  test('a missing or empty file is a problem, not an exception', () {
    expect(runVerifyArtifact(['${temp.path}/nope', 'linux-x64'], out: out), 1);
    expect(out.toString(), contains('cannot read'));
    final empty = write([]);
    expect(runVerifyArtifact([empty.path, 'linux-x64'], out: out), 1);
    expect(out.toString(), contains('empty'));
  });

  test('a wrong argument count or an unknown key is a usage error', () {
    expect(runVerifyArtifact(const [], out: out), 64);
    expect(out.toString(), contains('usage'));
    final file = write(soundLibraryFor('linux-x64'));
    expect(runVerifyArtifact([file.path, 'plan9-x64'], out: out), 64);
  });
}
