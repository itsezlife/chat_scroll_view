import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/artifact_check.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/targets.dart';

const _androidArm64 = LottieNativeTarget(OS.android, Architecture.arm64);
const _androidX64 = LottieNativeTarget(OS.android, Architecture.x64);

/// A minimal little-endian ELF64 file: the header and one program header per
/// entry of [segments] (`type`, `align`), nothing else. Offsets follow the
/// ELF64 specification: `e_phoff` at 0x20, `e_machine` at 0x12, `e_phentsize`
/// at 0x36, `e_phnum` at 0x38; a program header has `p_type` at 0 and
/// `p_align` at 0x30.
Uint8List _elf({required int machine, required List<(int, int)> segments}) {
  const header = 64;
  const phSize = 56;
  final bytes = ByteData(header + phSize * segments.length);
  bytes.setUint32(0, 0x464c457f, Endian.little); // 7f 'E' 'L' 'F'
  bytes.setUint8(4, 2); // ELFCLASS64
  bytes.setUint8(5, 1); // little endian
  bytes.setUint16(0x12, machine, Endian.little);
  bytes.setUint64(0x20, header, Endian.little);
  bytes.setUint16(0x36, phSize, Endian.little);
  bytes.setUint16(0x38, segments.length, Endian.little);
  for (var i = 0; i < segments.length; i++) {
    final at = header + phSize * i;
    bytes.setUint32(at, segments[i].$1, Endian.little);
    bytes.setUint64(at + 0x30, segments[i].$2, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

const _ptLoad = 1;
const _ptDynamic = 2;
const _aarch64 = 0xb7;
const _x8664 = 0x3e;

/// A thin 64-bit little-endian Mach-O header.
Uint8List _macho(int cpuType) {
  final bytes = ByteData(32);
  bytes.setUint32(0, 0xfeedfacf, Endian.little);
  bytes.setUint32(4, cpuType, Endian.little);
  return bytes.buffer.asUint8List();
}

/// A big-endian fat header listing [cpuTypes].
Uint8List _fat(List<int> cpuTypes, {bool fat64 = false}) {
  final entry = fat64 ? 32 : 20;
  final bytes = ByteData(8 + entry * cpuTypes.length);
  bytes.setUint32(0, fat64 ? 0xcafebabf : 0xcafebabe);
  bytes.setUint32(4, cpuTypes.length);
  for (var i = 0; i < cpuTypes.length; i++) {
    bytes.setUint32(8 + entry * i, cpuTypes[i]);
  }
  return bytes.buffer.asUint8List();
}

const _armCpu = 0x0100000c;
const _x64Cpu = 0x01000007;

void main() {
  group('artifactProblem for Android (ELF)', () {
    test('passes 16 KB aligned segments of the right machine', () {
      final bytes = _elf(
        machine: _aarch64,
        segments: [(_ptLoad, 0x4000), (_ptLoad, 0x4000), (_ptDynamic, 8)],
      );

      expect(artifactProblem(bytes, _androidArm64), isNull);
    });

    test('passes alignment above 16 KB', () {
      final bytes = _elf(machine: _x8664, segments: [(_ptLoad, 0x10000)]);

      expect(artifactProblem(bytes, _androidX64), isNull);
    });

    test('fails 4 KB aligned segments, naming the alignment and the rule', () {
      final bytes = _elf(
        machine: _aarch64,
        segments: [(_ptLoad, 0x4000), (_ptLoad, 0x1000)],
      );

      expect(
        artifactProblem(bytes, _androidArm64),
        allOf(contains('0x1000'), contains('16 KB')),
      );
    });

    test('ignores the alignment of segments that are not loaded', () {
      final bytes = _elf(
        machine: _aarch64,
        segments: [(_ptLoad, 0x4000), (_ptDynamic, 1)],
      );

      expect(artifactProblem(bytes, _androidArm64), isNull);
    });

    test('fails a library of the other architecture', () {
      final bytes = _elf(machine: _x8664, segments: [(_ptLoad, 0x4000)]);

      expect(
        artifactProblem(bytes, _androidArm64),
        allOf(contains('0x3e'), contains('0xb7')),
      );
    });

    test('fails a file with no loadable segment', () {
      final bytes = _elf(machine: _aarch64, segments: [(_ptDynamic, 8)]);

      expect(artifactProblem(bytes, _androidArm64), contains('PT_LOAD'));
    });

    test('fails what is not an ELF64 little-endian file', () {
      expect(artifactProblem(Uint8List(10), _androidArm64), contains('ELF'));
      final elf32 = _elf(machine: _aarch64, segments: [(_ptLoad, 0x4000)])
        ..[4] = 1;
      expect(artifactProblem(elf32, _androidArm64), contains('ELF'));
    });

    test('fails a truncated program header table', () {
      final bytes = _elf(
        machine: _aarch64,
        segments: [(_ptLoad, 0x4000), (_ptLoad, 0x4000)],
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
      expect(artifactProblem(_macho(_armCpu), macArm), isNull);
      expect(artifactProblem(_macho(_x64Cpu), macX64), isNull);
      expect(artifactProblem(_macho(_x64Cpu), iosSim), isNull);
    });

    test('fails a thin file of the other CPU', () {
      expect(
        artifactProblem(_macho(_x64Cpu), macArm),
        allOf(contains('x86_64'), contains('arm64')),
      );
    });

    test('passes a fat file that holds the CPU, thin or 64-bit offsets', () {
      expect(artifactProblem(_fat([_x64Cpu, _armCpu]), macArm), isNull);
      expect(
        artifactProblem(_fat([_x64Cpu, _armCpu], fat64: true), macArm),
        isNull,
      );
    });

    test('fails a fat file without the CPU', () {
      expect(artifactProblem(_fat([_x64Cpu]), macArm), contains('arm64'));
    });

    test('fails what is not a 64-bit Mach-O file', () {
      expect(artifactProblem(Uint8List(3), macArm), contains('Mach-O'));
      expect(
        artifactProblem(_elf(machine: _aarch64, segments: []), macArm),
        contains('Mach-O'),
      );
    });

    test('fails a fat header that lists more slices than it holds', () {
      final bytes = _fat([_armCpu]);
      bytes[7] = 9;

      expect(artifactProblem(bytes, macArm), contains('truncated'));
    });
  });

  group('artifactProblem elsewhere', () {
    test('checks nothing for Linux and Windows', () {
      for (final os in [OS.linux, OS.windows]) {
        expect(
          artifactProblem(
            Uint8List(4),
            LottieNativeTarget(os, Architecture.x64),
          ),
          isNull,
        );
      }
    });
  });
}
