import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_manifest.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/source_hash.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../native/tool/source_hash.dart' show runSourceHashCommand;

const _cargoToml = '[package]\nname = "x"\nversion = "1.2.3"\n';

/// Computed with an independent implementation (python hashlib) over the
/// `lottie-native-source-v2` listing documented in source_hash.dart, for the
/// tree the test writes.
const _knownHash =
    'b5822682b007a5206702975d8697ba61a6fec4ab0af1e673cd315ccf1e36fe37';

void _write(Directory root, String path, String content) {
  File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

Directory _tree(Directory root, {bool reversed = false}) {
  final files = <String, String>{
    'Cargo.toml': _cargoToml,
    'Cargo.lock': 'b',
    'include/h.h': 'd',
    'src/x.rs': 'cc',
  };
  final entries = files.entries.toList();
  for (final e in reversed ? entries.reversed : entries) {
    _write(root, e.key, e.value);
  }
  return root;
}

void main() {
  late Directory temp;
  late Directory native;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('source_hash_test');
    native = Directory('${temp.path}/native')..createSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  group('computeSourceHash', () {
    test('matches an independently computed value', () {
      _write(native, 'Cargo.toml', '[package]\nversion = "1.2.3"\n');
      _write(native, 'Cargo.lock', 'b');
      _write(native, 'include/h.h', 'd');
      _write(native, 'src/x.rs', 'cc');

      expect(computeSourceHash(native), _knownHash);
    });

    test('is the same for the same tree whatever the creation order', () {
      final other = Directory('${temp.path}/other')..createSync();
      _tree(native);
      _tree(other, reversed: true);

      expect(computeSourceHash(native), computeSourceHash(other));
    });

    test('changes when one byte of a source changes', () {
      _tree(native);
      final before = computeSourceHash(native);

      _write(native, 'src/x.rs', 'cd');

      expect(computeSourceHash(native), isNot(before));
    });

    test('changes when a file is renamed', () {
      _tree(native);
      final before = computeSourceHash(native);

      File('${native.path}/src/x.rs').renameSync('${native.path}/src/y.rs');

      expect(computeSourceHash(native), isNot(before));
    });

    test('changes when a file is added under src or include', () {
      _tree(native);
      final before = computeSourceHash(native);

      _write(native, 'include/more.h', '');

      expect(computeSourceHash(native), isNot(before));
    });

    test('does not move content between neighbouring files', () {
      // Without the length framing, "ab"+"c" and "a"+"bc" would collide.
      _tree(native);
      _write(native, 'src/a.rs', 'ab');
      _write(native, 'src/b.rs', 'c');
      final one = computeSourceHash(native);
      _write(native, 'src/a.rs', 'a');
      _write(native, 'src/b.rs', 'bc');

      expect(computeSourceHash(native), isNot(one));
    });

    test('cannot be fooled by a path that imitates the framing', () {
      // Under the first framing (`path LF length LF bytes LF`) these two
      // listings were the same byte string: a file named like the head of
      // the next record swallowed it. They are different trees.
      final payload = utf8.encode('fn main() {}');
      final oneFile = hashSourceListing([(path: 'a\n1\nZ\nb', bytes: payload)]);
      final twoFiles = hashSourceListing([
        (path: 'a', bytes: utf8.encode('Z')),
        (path: 'b', bytes: payload),
      ]);

      expect(oneFile, isNot(twoFiles));
    });

    test('starts from a version line, so a format change is a new hash', () {
      // An empty listing is the version line alone.
      expect(
        hashSourceListing(const []),
        sha256.convert(utf8.encode('lottie-native-source-v2\n')).toString(),
      );
    });

    test('counts the length of a path in bytes, not characters', () {
      // "é" is two bytes in UTF-8: 2:é 1:x, never 1:é.
      final listing = utf8.encode('lottie-native-source-v2\n2:\u00e91:x');
      expect(
        hashSourceListing([(path: '\u00e9', bytes: utf8.encode('x'))]),
        sha256.convert(listing).toString(),
      );
    });

    test(
      'refuses a source path with a control character',
      () {
        _tree(native);
        _write(native, 'src/a\nb.rs', 'x');

        expect(() => computeSourceHash(native), throwsFormatException);
      },
      skip: Platform.isWindows
          ? 'Windows forbids control characters in names'
          : null,
    );

    test('ignores everything that is not an input of the build', () {
      _tree(native);
      final before = computeSourceHash(native);

      _write(native, 'prebuilts.json', '{}');
      _write(native, 'tests/t.rs', 'x');
      _write(native, 'target/debug/y', 'x');
      _write(native, 'tool/source_hash.dart', 'x');

      expect(computeSourceHash(native), before);
    });
  });

  group('readCrateVersion', () {
    test('reads the package version from Cargo.toml', () {
      _tree(native);

      expect(readCrateVersion(native), '1.2.3');
    });

    test('fails when Cargo.toml has no package version', () {
      _write(native, 'Cargo.toml', '[lib]\nname = "x"\n');

      expect(() => readCrateVersion(native), throwsFormatException);
    });

    test('ignores a dependency version above the package one', () {
      _write(
        native,
        'Cargo.toml',
        '[dependencies]\nfoo = { version = "9" }\n[package]\nversion = "1.0.0"\n',
      );

      expect(readCrateVersion(native), '1.0.0');
    });
  });

  group('runSourceHashTool', () {
    void writeManifest({String? sourceHash}) => _write(
      native,
      'prebuilts.json',
      jsonEncode({
        'schema': 1,
        'crateVersion': '0.0.1',
        'sourceHash': sourceHash ?? '00' * 32,
        'baseUrl': 'https://example.com/p/',
        'artifacts': {
          'linux-x64': {'file': 'lib.so', 'sha256': 'ab' * 32, 'size': 3},
        },
        'unknownKey': true,
      }),
    );

    test('prints the hash and touches nothing without --write', () {
      _tree(native);
      writeManifest();
      final manifestBefore = File(
        '${native.path}/prebuilts.json',
      ).readAsStringSync();
      final out = StringBuffer();

      final code = runSourceHashTool(const [], native: native, out: out);

      expect(code, 0);
      expect(out.toString().trim(), computeSourceHash(native));
      expect(
        File('${native.path}/prebuilts.json').readAsStringSync(),
        manifestBefore,
      );
    });

    test('--write updates sourceHash and crateVersion and keeps the rest', () {
      _tree(native);
      writeManifest();

      final code = runSourceHashTool(
        const ['--write'],
        native: native,
        out: StringBuffer(),
      );

      final json =
          jsonDecode(File('${native.path}/prebuilts.json').readAsStringSync())
              as Map<String, Object?>;
      expect(code, 0);
      expect(json['sourceHash'], computeSourceHash(native));
      expect(json['crateVersion'], '1.2.3');
      expect(json['baseUrl'], 'https://example.com/p/');
      expect(json['unknownKey'], true);
      expect(
        PrebuiltManifest.parse(
          File('${native.path}/prebuilts.json').readAsStringSync(),
        ).artifactFor('linux-x64')!.file,
        'lib.so',
      );
    });

    test('a hash written by --write is then current', () {
      _tree(native);
      writeManifest();
      runSourceHashTool(const ['--write'], native: native, out: StringBuffer());
      final written = PrebuiltManifest.parse(
        File('${native.path}/prebuilts.json').readAsStringSync(),
      ).sourceHash;

      _write(native, 'src/x.rs', 'changed');

      expect(written, isNot(computeSourceHash(native)));
    });

    test('an unknown argument exits 64 and says the usage', () {
      _tree(native);
      final out = StringBuffer();

      final code = runSourceHashTool(
        const ['--bogus'],
        native: native,
        out: out,
      );

      expect(code, 64);
      expect(out.toString(), contains('--write'));
    });
  });

  group('runSourceHashCommand --check', () {
    void writeManifest(Object? sourceHash) => _write(
      native,
      'prebuilts.json',
      jsonEncode({
        'schema': 1,
        'crateVersion': '1.2.3',
        'sourceHash': sourceHash,
        'baseUrl': '',
        'artifacts': <String, Object?>{},
      }),
    );

    int check(StringBuffer out, [List<String> args = const ['--check']]) =>
        runSourceHashCommand(args, native: native, out: out);

    test('passes when the recorded hash is the hash of the sources', () {
      _tree(native);
      writeManifest(computeSourceHash(native));

      expect(check(StringBuffer()), 0);
    });

    test('fails when the sources changed after the hash was recorded', () {
      _tree(native);
      final recorded = computeSourceHash(native);
      writeManifest(recorded);
      _write(native, 'src/x.rs', 'changed');
      final out = StringBuffer();

      final code = check(out);

      expect(code, 1);
      expect(out.toString(), contains('--write'));
      expect(out.toString(), contains(recorded));
    });

    test('passes with an empty hash: nothing is published on purpose', () {
      _tree(native);
      writeManifest('');

      expect(check(StringBuffer()), 0);
    });

    test('fails when the manifest is missing', () {
      _tree(native);
      final out = StringBuffer();

      expect(check(out), 1);
      expect(out.toString(), contains('prebuilts.json'));
    });

    test('fails when the manifest is not JSON', () {
      _tree(native);
      _write(native, 'prebuilts.json', '{nope');

      expect(check(StringBuffer()), 1);
    });

    test('fails when sourceHash is not a string', () {
      _tree(native);
      writeManifest(5);

      expect(check(StringBuffer()), 1);
    });

    test('--check does not combine with --write', () {
      _tree(native);
      writeManifest(computeSourceHash(native));

      expect(check(StringBuffer(), const ['--check', '--write']), 64);
    });

    test('other arguments still reach the hash tool', () {
      _tree(native);
      final out = StringBuffer();

      expect(check(out, const []), 0);
      expect(out.toString().trim(), computeSourceHash(native));
    });
  });
}
