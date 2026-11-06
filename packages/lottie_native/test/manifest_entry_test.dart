import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/manifest_entry.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_manifest.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('manifest_entry'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('prints file name, sha256 and size of a file', () async {
    final file = File('${temp.path}/libx.so')..writeAsStringSync('abc');

    final entry =
        jsonDecode(await manifestEntryFor(file)) as Map<String, Object?>;

    expect(entry, {
      'file': 'libx.so',
      // The standard SHA-256 test vector for "abc".
      'sha256':
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'size': 3,
    });
  });

  test('the entry is accepted by the manifest parser', () async {
    final file = File('${temp.path}/libx.so')..writeAsStringSync('abc');
    final entry = jsonDecode(await manifestEntryFor(file));

    final manifest = PrebuiltManifest.parse(
      jsonEncode({
        'schema': 1,
        'crateVersion': '0.1.0',
        'sourceHash': '00' * 32,
        'baseUrl': 'https://example.com/',
        'artifacts': {'linux-x64': entry},
      }),
    );

    expect(manifest.artifactFor('linux-x64')!.size, 3);
  });

  test('a missing file fails with its path', () {
    expect(
      manifestEntryFor(File('${temp.path}/nope')),
      throwsA(isA<FileSystemException>()),
    );
  });
}
