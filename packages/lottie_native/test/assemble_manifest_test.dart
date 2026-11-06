import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_manifest.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/source_hash.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../native/tool/assemble_manifest.dart' show runAssembleManifest;

const _elf = [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0];
const _macho = [0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1];
const _macFat = [0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 2];
const _pe = [0x4d, 0x5a, 0x90, 0, 3, 0, 0, 0];

const _baseUrl = 'https://example.com/lottie_native/0.1.0/';

void main() {
  late Directory temp;
  late Directory native;
  late Directory libs;
  late StringBuffer out;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('assemble_manifest');
    native = Directory('${temp.path}/native')..createSync();
    File(
      '${native.path}/Cargo.toml',
    ).writeAsStringSync('[package]\nname = "x"\nversion = "1.2.3"\n');
    File('${native.path}/Cargo.lock').writeAsStringSync('lock');
    Directory('${native.path}/src').createSync();
    File('${native.path}/src/x.rs').writeAsStringSync('fn main() {}');
    libs = Directory('${temp.path}/libs')..createSync();
    out = StringBuffer();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File lib(String name, List<int> header, {int padding = 4}) =>
      File('${libs.path}/$name')
        ..writeAsBytesSync([...header, ...List.filled(padding, 7)]);

  Future<int> run([List<String> extra = const []]) => runAssembleManifest(
    [libs.path, '--base-url', _baseUrl, ...extra],
    native: native,
    out: out,
  );

  Map<String, Object?> manifestJson() =>
      jsonDecode(File('${native.path}/prebuilts.json').readAsStringSync())
          as Map<String, Object?>;

  test('writes a manifest the hook parses, with sizes and hashes', () async {
    lib('libchat_lottie-linux-x64.so', _elf);
    lib('libchat_lottie-macos-arm64.dylib', _macho, padding: 9);
    lib('libchat_lottie-windows-x64.dll', _pe);

    final code = await run();

    expect(code, 0, reason: out.toString());
    final text = File('${native.path}/prebuilts.json').readAsStringSync();
    final manifest = PrebuiltManifest.parse(text);
    expect(manifest.crateVersion, '1.2.3');
    expect(manifest.sourceHash, computeSourceHash(native));
    expect(manifest.baseUrl, Uri.parse(_baseUrl));
    expect(manifest.artifacts.keys, {
      'linux-x64',
      'macos-arm64',
      'windows-x64',
    });
    expect(
      manifest.artifactFor('macos-arm64')!.file,
      ['libchat_lottie-macos-arm64.dylib'].single,
    );
    expect(manifest.artifactFor('macos-arm64')!.size, 17);
    expect(manifest.artifactFor('linux-x64')!.size, 12);
    expect(text, endsWith('}\n'));
  });

  test('sha256 is that of the file bytes', () async {
    lib('libchat_lottie-linux-x64.so', _elf);

    await run();

    // Computed with an independent implementation (python hashlib) over the
    // twelve bytes the test writes.
    final entry = (manifestJson()['artifacts']! as Map)['linux-x64'] as Map;
    expect(
      entry['sha256'],
      '8ce3faedc9c6c7e2a9f4ae2595d51339fd2709d7bf0dbe839a797804d991e7d7',
    );
  });

  test('a re-run over the same files is byte for byte the same', () async {
    lib('libchat_lottie-linux-x64.so', _elf);
    lib('libchat_lottie-android-arm64.so', _elf);
    await run();
    final first = File('${native.path}/prebuilts.json').readAsStringSync();

    final code = await run();

    expect(code, 0);
    expect(File('${native.path}/prebuilts.json').readAsStringSync(), first);
  });

  test('accepts every format its platform uses', () async {
    lib('libchat_lottie-ios-arm64.dylib', _macFat);
    lib('libchat_lottie-ios-arm64-simulator.dylib', _macho);
    lib('libchat_lottie-android-x64.so', _elf);

    expect(await run(), 0, reason: out.toString());
  });

  group('--require', () {
    test('passes when every required key has a file', () async {
      lib('libchat_lottie-linux-x64.so', _elf);
      lib('libchat_lottie-macos-arm64.dylib', _macho);

      final code = await run(['--require', 'linux-x64,macos-arm64']);

      expect(code, 0, reason: out.toString());
    });

    test('fails naming the missing key, and writes nothing', () async {
      lib('libchat_lottie-linux-x64.so', _elf);

      final code = await run(['--require', 'linux-x64,windows-x64']);

      expect(code, 1);
      expect(out.toString(), contains('windows-x64'));
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });

    test('without it a subset is a valid manifest', () async {
      lib('libchat_lottie-linux-x64.so', _elf);

      expect(await run(), 0);
    });

    test('an unknown required key is a usage error', () async {
      lib('libchat_lottie-linux-x64.so', _elf);

      expect(await run(['--require', 'plan9-x64']), 64);
    });
  });

  group('refuses', () {
    test('two files that claim one key', () async {
      lib('libchat_lottie-linux-x64.so', _elf);
      lib('libchat_lottie-linux-x64.dll', _pe);

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('linux-x64'));
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });

    test('an empty file', () async {
      File('${libs.path}/libchat_lottie-linux-x64.so').createSync();

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('empty'));
    });

    test('an ELF file named for a macOS key', () async {
      lib('libchat_lottie-macos-arm64.dylib', _elf);

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('Mach-O'));
    });

    test('a Mach-O file named for a linux key', () async {
      lib('libchat_lottie-linux-arm64.so', _macho);

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('ELF'));
    });

    test('a file shorter than its magic', () async {
      File(
        '${libs.path}/libchat_lottie-windows-x64.dll',
      ).writeAsBytesSync([0x4d]);

      expect(await run(), 1);
    });

    test('a file name that is no library of the vocabulary', () async {
      lib('libchat_lottie-plan9-x64.so', _elf);

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('libchat_lottie-plan9-x64.so'));
    });

    test('a stray file in the directory', () async {
      lib('libchat_lottie-linux-x64.so', _elf);
      File('${libs.path}/notes.txt').writeAsStringSync('x');

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('notes.txt'));
    });

    test('an empty directory', () async {
      expect(await run(), 1);
    });

    test('a base URL the hook would refuse', () async {
      lib('libchat_lottie-linux-x64.so', _elf);

      final code = await runAssembleManifest(
        [libs.path, '--base-url', 'http://example.com/no-slash'],
        native: native,
        out: out,
      );

      expect(code, 1);
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });

    test('and reports every problem, not only the first', () async {
      lib('libchat_lottie-linux-x64.so', _macho);
      lib('libchat_lottie-macos-arm64.dylib', _elf);

      await run();

      expect(out.toString(), contains('linux-x64'));
      expect(out.toString(), contains('macos-arm64'));
    });
  });

  group('usage', () {
    test('no directory', () async {
      final code = await runAssembleManifest(
        const ['--base-url', _baseUrl],
        native: native,
        out: out,
      );

      expect(code, 64);
      expect(out.toString(), contains('usage'));
    });

    test('no base URL', () async {
      lib('libchat_lottie-linux-x64.so', _elf);

      final code = await runAssembleManifest(
        [libs.path],
        native: native,
        out: out,
      );

      expect(code, 64);
    });

    test('an unknown flag', () async {
      expect(await run(['--bogus']), 64);
    });

    test('--out writes elsewhere and leaves the committed manifest', () async {
      lib('libchat_lottie-linux-x64.so', _elf);
      final target = '${temp.path}/assembled.json';

      final code = await run(['--out', target]);

      expect(code, 0);
      expect(File(target).existsSync(), isTrue);
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });
  });
}
