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
import '../hook/src/targets.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../native/tool/assemble_manifest.dart' show runAssembleManifest;
import 'support/library_headers.dart';

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

  /// Writes [name] with [bytes], or a sound header for the key in its name.
  File lib(String name, [List<int>? bytes]) {
    final key = RegExp(
      r'libchat_lottie-(.+)\.\w+$',
    ).firstMatch(name)!.group(1)!;
    return File('${libs.path}/$name')
      ..writeAsBytesSync(bytes ?? soundLibraryFor(key));
  }

  Future<int> run([List<String> extra = const []]) => runAssembleManifest(
    [libs.path, '--base-url', _baseUrl, ...extra],
    native: native,
    out: out,
  );

  Map<String, Object?> manifestJson() =>
      jsonDecode(File('${native.path}/prebuilts.json').readAsStringSync())
          as Map<String, Object?>;

  test('writes a manifest the hook parses, with sizes and hashes', () async {
    lib('libchat_lottie-linux-x64.so');
    lib('libchat_lottie-macos-arm64.dylib');
    lib('libchat_lottie-windows-x64.dll');

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
    expect(
      manifest.artifactFor('macos-arm64')!.size,
      soundLibraryFor('macos-arm64').length,
    );
    expect(
      manifest.artifactFor('linux-x64')!.size,
      soundLibraryFor('linux-x64').length,
    );
    expect(text, endsWith('}\n'));
  });

  test('sha256 is that of the file bytes', () async {
    lib('libchat_lottie-linux-x64.so');

    await run();

    // Computed with an independent implementation (python hashlib) over the
    // 120 bytes of ELF header the test writes.
    final entry = (manifestJson()['artifacts']! as Map)['linux-x64'] as Map;
    expect(
      entry['sha256'],
      'cdd02d6366c31377bb29153737e6e3ad9aaa415a6f98b3edca4046c43a7690c9',
    );
  });

  test('a re-run over the same files is byte for byte the same', () async {
    lib('libchat_lottie-linux-x64.so');
    lib('libchat_lottie-android-arm64.so');
    await run();
    final first = File('${native.path}/prebuilts.json').readAsStringSync();

    final code = await run();

    expect(code, 0);
    expect(File('${native.path}/prebuilts.json').readAsStringSync(), first);
  });

  test('accepts every format its platform uses', () async {
    lib(
      'libchat_lottie-ios-arm64.dylib',
      fatLibrary([machoArmCpu, machoX64Cpu]),
    );
    lib('libchat_lottie-ios-arm64-simulator.dylib');
    lib('libchat_lottie-android-x64.so');

    expect(await run(), 0, reason: out.toString());
  });

  group('--require', () {
    test('passes when every required key has a file', () async {
      lib('libchat_lottie-linux-x64.so');
      lib('libchat_lottie-macos-arm64.dylib');

      final code = await run(['--require', 'linux-x64,macos-arm64']);

      expect(code, 0, reason: out.toString());
    });

    test('fails naming the missing key, and writes nothing', () async {
      lib('libchat_lottie-linux-x64.so');

      final code = await run(['--require', 'linux-x64,windows-x64']);

      expect(code, 1);
      expect(out.toString(), contains('windows-x64'));
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });

    test('without it a subset is a valid manifest', () async {
      lib('libchat_lottie-linux-x64.so');

      expect(await run(), 0);
    });

    test('an unknown required key is a usage error', () async {
      lib('libchat_lottie-linux-x64.so');

      expect(await run(['--require', 'plan9-x64']), 64);
    });
  });

  group('--require-all', () {
    void writeEvery({String? except}) {
      for (final key in LottieNativeTarget.keys) {
        if (key == except) continue;
        final ext = key.startsWith('windows')
            ? 'dll'
            : key.startsWith('linux') || key.startsWith('android')
            ? 'so'
            : 'dylib';
        lib('libchat_lottie-$key.$ext');
      }
    }

    test('passes when every key the tool knows has a file', () async {
      writeEvery();

      final code = await run(['--require-all']);

      expect(code, 0, reason: out.toString());
      expect(manifestJson()['artifacts'], hasLength(10));
    });

    test('fails naming the one key that is missing', () async {
      writeEvery(except: 'ios-x64-simulator');

      final code = await run(['--require-all']);

      expect(code, 1);
      expect(out.toString(), contains('ios-x64-simulator: no library'));
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });
  });

  group('refuses a library that does not fit its key', () {
    test('an ELF file of the other machine', () async {
      lib('libchat_lottie-linux-x64.so', soundElf(machine: elfAarch64));

      final code = await run();

      expect(code, 1);
      expect(out.toString(), allOf(contains('linux-x64'), contains('0xb7')));
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });

    test('an Android library on 4 KB pages', () async {
      lib(
        'libchat_lottie-android-arm64.so',
        elfLibrary(machine: elfAarch64, segments: [(ptLoad, 0x1000)]),
      );

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('16 KB'));
    });

    test('a Mach-O file of the other CPU', () async {
      lib('libchat_lottie-macos-arm64.dylib', machoLibrary(machoX64Cpu));

      expect(await run(), 1);
      expect(out.toString(), contains('x86_64'));
    });

    test('a PE file built for ARM64 under windows-x64', () async {
      lib('libchat_lottie-windows-x64.dll', peLibrary(machine: peArm64));

      expect(await run(), 1);
      expect(out.toString(), contains('0x8664'));
    });
  });

  group('refuses', () {
    test('two files that claim one key', () async {
      lib('libchat_lottie-linux-x64.so');
      lib('libchat_lottie-linux-x64.dll', peLibrary(machine: peAmd64));

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
      lib('libchat_lottie-macos-arm64.dylib', soundElf());

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('Mach-O'));
    });

    test('a Mach-O file named for a linux key', () async {
      lib('libchat_lottie-linux-arm64.so', machoLibrary(machoArmCpu));

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
      lib('libchat_lottie-plan9-x64.so', soundElf());

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('libchat_lottie-plan9-x64.so'));
    });

    test('a stray file in the directory', () async {
      lib('libchat_lottie-linux-x64.so');
      File('${libs.path}/notes.txt').writeAsStringSync('x');

      final code = await run();

      expect(code, 1);
      expect(out.toString(), contains('notes.txt'));
    });

    test('an empty directory', () async {
      expect(await run(), 1);
    });

    test('a base URL the hook would refuse', () async {
      lib('libchat_lottie-linux-x64.so');

      final code = await runAssembleManifest(
        [libs.path, '--base-url', 'http://example.com/no-slash'],
        native: native,
        out: out,
      );

      expect(code, 1);
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });

    test('and reports every problem, not only the first', () async {
      lib('libchat_lottie-linux-x64.so', machoLibrary(machoArmCpu));
      lib('libchat_lottie-macos-arm64.dylib', soundElf());

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
      lib('libchat_lottie-linux-x64.so');

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
      lib('libchat_lottie-linux-x64.so');
      final target = '${temp.path}/assembled.json';

      final code = await run(['--out', target]);

      expect(code, 0);
      expect(File(target).existsSync(), isTrue);
      expect(File('${native.path}/prebuilts.json').existsSync(), isFalse);
    });
  });
}
