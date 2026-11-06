/// A cheap check of a freshly built library's header, so a wrong-architecture
/// or mis-aligned file fails the build instead of shipping.
///
/// Android: every loadable segment must be aligned to 16 KB (Google Play
/// refuses 64-bit apps whose libraries are not) and the machine must be the
/// target's. Apple: the Mach-O CPU must be the target's. Pure Dart over the
/// header bytes, so it is tested on handcrafted fixtures.
library;

import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';

import 'targets.dart';

/// What is wrong with the library [bytes] for [target], or null when it is
/// fine (or when nothing is checked for the target: Linux and Windows).
String? artifactProblem(Uint8List bytes, LottieNativeTarget target) =>
    switch (target.os) {
      OS.android => _elfProblem(bytes, target.arch),
      OS.macOS || OS.iOS => _machOProblem(bytes, target.arch),
      _ => null,
    };

// --- ELF -------------------------------------------------------------------

const _elfMachines = {Architecture.arm64: 0xb7, Architecture.x64: 0x3e};
const _ptLoad = 1;
const _sixteenKb = 0x4000;

String? _elfProblem(Uint8List bytes, Architecture arch) {
  const headerSize = 64;
  if (bytes.length < headerSize ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 || // E
      bytes[2] != 0x4c || // L
      bytes[3] != 0x46 || // F
      bytes[4] != 2 || // 64-bit
      bytes[5] != 1) {
    // little endian
    return 'the library is not a little-endian ELF64 file';
  }
  final data = ByteData.sublistView(bytes);
  final machine = data.getUint16(0x12, Endian.little);
  final expected = _elfMachines[arch];
  if (machine != expected) {
    return 'the library is built for ELF machine 0x${machine.toRadixString(16)} '
        'but the target needs 0x${expected?.toRadixString(16)} ($arch)';
  }

  final tableOffset = data.getUint64(0x20, Endian.little);
  final entrySize = data.getUint16(0x36, Endian.little);
  final count = data.getUint16(0x38, Endian.little);
  var loads = 0;
  for (var i = 0; i < count; i++) {
    final at = tableOffset + entrySize * i;
    if (entrySize < 0x38 || at + entrySize > bytes.length) {
      return 'the ELF program header table is truncated';
    }
    if (data.getUint32(at, Endian.little) != _ptLoad) continue;
    loads++;
    final align = data.getUint64(at + 0x30, Endian.little);
    if (align < _sixteenKb) {
      return 'a loadable segment is aligned to 0x${align.toRadixString(16)}, '
          'below 0x4000: Google Play requires 16 KB page alignment '
          '(-Wl,-z,max-page-size=16384)';
    }
  }
  return loads == 0 ? 'the library has no PT_LOAD segment' : null;
}

// --- Mach-O ----------------------------------------------------------------

const _cpuTypes = {
  Architecture.arm64: 0x0100000c,
  Architecture.x64: 0x01000007,
};

String? _machOProblem(Uint8List bytes, Architecture arch) {
  final expected = _cpuTypes[arch]!;
  if (bytes.length < 8) return 'the library is not a 64-bit Mach-O file';
  final data = ByteData.sublistView(bytes);

  final cpus = <int>[];
  switch (data.getUint32(0)) {
    // Fat headers are big endian; 0xcafebabf has 32-byte entries.
    case final magic when magic == 0xcafebabe || magic == 0xcafebabf:
      final entrySize = magic == 0xcafebabe ? 20 : 32;
      final count = data.getUint32(4);
      if (8 + entrySize * count > bytes.length) {
        return 'the Mach-O fat header is truncated';
      }
      for (var i = 0; i < count; i++) {
        cpus.add(data.getUint32(8 + entrySize * i));
      }
    default:
      if (data.getUint32(0, Endian.little) != 0xfeedfacf) {
        return 'the library is not a 64-bit Mach-O file';
      }
      cpus.add(data.getUint32(4, Endian.little));
  }
  if (cpus.contains(expected)) return null;
  String name(int cpu) => switch (cpu) {
    0x0100000c => 'arm64',
    0x01000007 => 'x86_64',
    _ => '0x${cpu.toRadixString(16)}',
  };
  return 'the Mach-O library holds ${cpus.map(name).join(', ')} but the '
      'target needs ${name(expected)}';
}
