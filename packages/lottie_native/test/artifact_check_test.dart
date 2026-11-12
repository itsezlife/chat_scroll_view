import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/artifact_check.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/targets.dart';
import 'support/library_headers.dart';

const _androidArm64 = LottieNativeTarget(OS.android, Architecture.arm64);
const _androidX64 = LottieNativeTarget(OS.android, Architecture.x64);

void main() {
  group('artifactProblem for Android (ELF)', () {
    test('passes 16 KB aligned segments of the right machine', () {
      final bytes = elfLibrary(
        machine: elfAarch64,
        segments: [(ptLoad, 0x4000), (ptLoad, 0x4000), (ptDynamic, 8)],
      );

      expect(artifactProblem(bytes, _androidArm64), isNull);
    });

    test('passes alignment above 16 KB', () {
      final bytes = elfLibrary(
        machine: elfX8664,
        segments: [(ptLoad, 0x10000)],
      );

      expect(artifactProblem(bytes, _androidX64), isNull);
    });

    test('fails 4 KB aligned segments, naming the alignment and the rule', () {
      final bytes = elfLibrary(
        machine: elfAarch64,
        segments: [(ptLoad, 0x4000), (ptLoad, 0x1000)],
      );

      expect(
        artifactProblem(bytes, _androidArm64),
        allOf(contains('0x1000'), contains('16 KB')),
      );
    });

    test('ignores the alignment of segments that are not loaded', () {
      final bytes = elfLibrary(
        machine: elfAarch64,
        segments: [(ptLoad, 0x4000), (ptDynamic, 1)],
      );

      expect(artifactProblem(bytes, _androidArm64), isNull);
    });

    test('fails a library of the other architecture', () {
      final bytes = elfLibrary(machine: elfX8664, segments: [(ptLoad, 0x4000)]);

      expect(
        artifactProblem(bytes, _androidArm64),
        allOf(contains('0x3e'), contains('0xb7')),
      );
    });

    test('fails a file with no loadable segment', () {
      final bytes = elfLibrary(machine: elfAarch64, segments: [(ptDynamic, 8)]);

      expect(artifactProblem(bytes, _androidArm64), contains('PT_LOAD'));
    });

    test('fails what is not an ELF64 little-endian file', () {
      expect(artifactProblem(Uint8List(10), _androidArm64), contains('ELF'));
      final elf32 = elfLibrary(
        machine: elfAarch64,
        segments: [(ptLoad, 0x4000)],
      )..[4] = 1;
      expect(artifactProblem(elf32, _androidArm64), contains('ELF'));
    });

    test('fails a truncated program header table', () {
      final bytes = elfLibrary(
        machine: elfAarch64,
        segments: [(ptLoad, 0x4000), (ptLoad, 0x4000)],
      );

      expect(
        artifactProblem(bytes.sublist(0, bytes.length - 10), _androidArm64),
        contains('truncated'),
      );
    });
  });

  group('artifactProblem for Apple targets (Mach-O)', () {
    const macArm = LottieNativeTarget(OS.macOS, Architecture.arm64);
    const macX64 = LottieNativeTarget(OS.macOS, Architecture.x64);
    const iosSim = LottieNativeTarget(
      OS.iOS,
      Architecture.x64,
      sdk: IOSSdk.iPhoneSimulator,
    );

    test('passes a thin file of the right CPU', () {
      expect(artifactProblem(machoLibrary(machoArmCpu), macArm), isNull);
      expect(artifactProblem(machoLibrary(machoX64Cpu), macX64), isNull);
      expect(artifactProblem(machoLibrary(machoX64Cpu), iosSim), isNull);
    });

    test('fails a thin file of the other CPU', () {
      expect(
        artifactProblem(machoLibrary(machoX64Cpu), macArm),
        allOf(contains('x86_64'), contains('arm64')),
      );
    });

    test('passes a fat file that holds the CPU, thin or 64-bit offsets', () {
      expect(
        artifactProblem(fatLibrary([machoX64Cpu, machoArmCpu]), macArm),
        isNull,
      );
      expect(
        artifactProblem(
          fatLibrary([machoX64Cpu, machoArmCpu], fat64: true),
          macArm,
        ),
        isNull,
      );
    });

    test('fails a fat file without the CPU', () {
      expect(
        artifactProblem(fatLibrary([machoX64Cpu]), macArm),
        contains('arm64'),
      );
    });

    test('fails what is not a 64-bit Mach-O file', () {
      expect(artifactProblem(Uint8List(3), macArm), contains('Mach-O'));
      expect(
        artifactProblem(elfLibrary(machine: elfAarch64, segments: []), macArm),
        contains('Mach-O'),
      );
    });

    test('fails a fat header that lists more slices than it holds', () {
      final bytes = fatLibrary([machoArmCpu]);
      bytes[7] = 9;

      expect(artifactProblem(bytes, macArm), contains('truncated'));
    });
  });

  group('artifactProblem for Linux (ELF machine only)', () {
    const linuxX64 = LottieNativeTarget(OS.linux, Architecture.x64);
    const linuxArm64 = LottieNativeTarget(OS.linux, Architecture.arm64);

    test('passes the right machine without asking for 16 KB alignment', () {
      final bytes = elfLibrary(machine: elfX8664, segments: [(ptLoad, 0x1000)]);

      expect(artifactProblem(bytes, linuxX64), isNull);
    });

    test('fails a library of the other architecture', () {
      expect(
        artifactProblem(soundElf(machine: elfAarch64), linuxX64),
        allOf(contains('0xb7'), contains('0x3e')),
      );
      expect(
        artifactProblem(soundElf(machine: elfX8664), linuxArm64),
        allOf(contains('0x3e'), contains('0xb7')),
      );
    });

    test('fails what is not an ELF64 little-endian file', () {
      expect(
        artifactProblem(machoLibrary(machoArmCpu), linuxX64),
        contains('ELF'),
      );
    });
  });

  group('artifactProblem for Windows (PE machine)', () {
    const windowsX64 = LottieNativeTarget(OS.windows, Architecture.x64);

    test('passes an x64 PE file', () {
      expect(artifactProblem(peLibrary(machine: peAmd64), windowsX64), isNull);
    });

    test('fails a PE file built for ARM64', () {
      expect(
        artifactProblem(peLibrary(machine: peArm64), windowsX64),
        allOf(contains('0xaa64'), contains('0x8664')),
      );
    });

    test('fails what is not a PE file', () {
      expect(artifactProblem(Uint8List(10), windowsX64), contains('PE'));
      expect(artifactProblem(soundElf(), windowsX64), contains('PE'));
      final noSignature = peLibrary(machine: peAmd64)..[0x80] = 0;
      expect(artifactProblem(noSignature, windowsX64), contains('PE'));
    });

    test('fails a file whose PE header lies beyond its end', () {
      final bytes = peLibrary(machine: peAmd64);
      ByteData.sublistView(bytes).setUint32(0x3c, 0xfffffff0, Endian.little);

      expect(artifactProblem(bytes, windowsX64), contains('PE'));
    });
  });
}
