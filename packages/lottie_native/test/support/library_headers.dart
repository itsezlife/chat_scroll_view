/// Handcrafted headers of native libraries for the tests: just enough of an
/// ELF64, Mach-O or PE file for the hook's header check, never a real library.
library;

import 'dart:typed_data';

const ptLoad = 1;
const ptDynamic = 2;
const elfAarch64 = 0xb7;
const elfX8664 = 0x3e;
const machoArmCpu = 0x0100000c;
const machoX64Cpu = 0x01000007;
const peAmd64 = 0x8664;
const peArm64 = 0xaa64;

/// A minimal little-endian ELF64 file: the header and one program header per
/// entry of [segments] (`type`, `align`), nothing else. Offsets follow the
/// ELF64 specification: `e_phoff` at 0x20, `e_machine` at 0x12, `e_phentsize`
/// at 0x36, `e_phnum` at 0x38; a program header has `p_type` at 0 and
/// `p_align` at 0x30.
Uint8List elfLibrary({
  required int machine,
  required List<(int, int)> segments,
}) {
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

/// An ELF64 library a Linux or Android target accepts: one 16 KB aligned
/// loadable segment of [machine].
Uint8List soundElf({int machine = elfX8664}) =>
    elfLibrary(machine: machine, segments: [(ptLoad, 0x4000)]);

/// A thin 64-bit little-endian Mach-O header.
Uint8List machoLibrary(int cpuType) {
  final bytes = ByteData(32);
  bytes.setUint32(0, 0xfeedfacf, Endian.little);
  bytes.setUint32(4, cpuType, Endian.little);
  return bytes.buffer.asUint8List();
}

/// A big-endian fat header listing [cpuTypes].
Uint8List fatLibrary(List<int> cpuTypes, {bool fat64 = false}) {
  final entry = fat64 ? 32 : 20;
  final bytes = ByteData(8 + entry * cpuTypes.length);
  bytes.setUint32(0, fat64 ? 0xcafebabf : 0xcafebabe);
  bytes.setUint32(4, cpuTypes.length);
  for (var i = 0; i < cpuTypes.length; i++) {
    bytes.setUint32(8 + entry * i, cpuTypes[i]);
  }
  return bytes.buffer.asUint8List();
}

/// A PE file: the `MZ` DOS header whose `e_lfanew` (0x3c) points at the
/// `PE\0\0` signature at [peOffset], followed by the COFF header whose first
/// field is the 16-bit machine.
Uint8List peLibrary({required int machine, int peOffset = 0x80}) {
  final bytes = ByteData(peOffset + 24);
  bytes.setUint16(0, 0x5a4d, Endian.little); // 'MZ'
  bytes.setUint32(0x3c, peOffset, Endian.little);
  bytes.setUint32(peOffset, 0x00004550, Endian.little); // 'PE\0\0'
  bytes.setUint16(peOffset + 4, machine, Endian.little);
  return bytes.buffer.asUint8List();
}

/// A header that [artifactProblem] accepts for the manifest [key].
Uint8List soundLibraryFor(String key) => switch (key) {
  'macos-arm64' ||
  'ios-arm64' ||
  'ios-arm64-simulator' => machoLibrary(machoArmCpu),
  'macos-x64' || 'ios-x64-simulator' => machoLibrary(machoX64Cpu),
  'android-arm64' || 'linux-arm64' => soundElf(machine: elfAarch64),
  'android-x64' || 'linux-x64' => soundElf(machine: elfX8664),
  'windows-x64' => peLibrary(machine: peAmd64),
  _ => throw ArgumentError.value(key, 'key', 'not a manifest key'),
};
