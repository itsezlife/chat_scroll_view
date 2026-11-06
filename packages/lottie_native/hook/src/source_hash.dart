/// The fingerprint of the crate sources, which ties a prebuilt library to the
/// code it was built from.
///
/// The hash is SHA-256 over this canonical listing: the files
/// `Cargo.toml`, `Cargo.lock`, everything under `include/` and everything
/// under `src/` (all relative to `native/`), sorted by their `/`-separated
/// relative path (string order), each contributing
///
/// ```text
/// <relative path> LF <byte length in decimal> LF <the file's bytes> LF
/// ```
///
/// The length frames the content so bytes cannot move between neighbours,
/// and the path makes a rename visible. Bytes are hashed as stored: a
/// checkout that rewrites line endings hashes differently and so falls back
/// to compiling, never to a library of unknown origin.
///
/// The hook and `native/tool/source_hash.dart` share this one definition.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The files that determine the compiled library, sorted by relative path.
///
/// Also what the hook declares as rebuild inputs, so the two cannot drift.
List<File> crateSourceFiles(Directory native) {
  final root = _slashed(native.path);
  final files = <File>[
    for (final name in const ['Cargo.toml', 'Cargo.lock'])
      File('${native.path}/$name'),
    for (final dir in const ['include', 'src'])
      if (Directory('${native.path}/$dir').existsSync())
        ...Directory(
          '${native.path}/$dir',
        ).listSync(recursive: true).whereType<File>(),
  ];
  return files
    ..sort((a, b) => _relative(root, a).compareTo(_relative(root, b)));
}

/// The hex SHA-256 of [native]'s sources, as documented above.
String computeSourceHash(Directory native) {
  final root = _slashed(native.path);
  // The sources are a few hundred kilobytes: one buffer, no streaming.
  final listing = BytesBuilder(copy: false);
  for (final file in crateSourceFiles(native)) {
    final bytes = file.readAsBytesSync();
    listing
      ..add(utf8.encode('${_relative(root, file)}\n${bytes.length}\n'))
      ..add(bytes)
      ..addByte(0x0a);
  }
  return sha256.convert(listing.takeBytes()).toString();
}

/// The `version` of the `[package]` table of `native/Cargo.toml`.
///
/// Throws [FormatException] when there is none.
String readCrateVersion(Directory native) {
  var inPackage = false;
  for (final line in File('${native.path}/Cargo.toml').readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[')) inPackage = trimmed == '[package]';
    if (!inPackage) continue;
    final match = RegExp(r'^version\s*=\s*"([^"]+)"').firstMatch(trimmed);
    if (match != null) return match.group(1)!;
  }
  throw const FormatException('Cargo.toml has no [package] version');
}

/// The command line of `native/tool/source_hash.dart`: prints the hash, or
/// with `--write` also records it and the crate version in
/// `prebuilts.json`. Returns the exit code.
int runSourceHashTool(
  List<String> args, {
  required Directory native,
  required StringSink out,
}) {
  final write = args.contains('--write');
  if (args.any((a) => a != '--write')) {
    out.writeln(
      'usage: dart native/tool/source_hash.dart [--write]\n'
      '  prints the sha256 of the crate sources; --write also records it '
      'and the crate version in native/prebuilts.json',
    );
    return 64;
  }
  final hash = computeSourceHash(native);
  if (write) {
    final file = File('${native.path}/prebuilts.json');
    final manifest =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    manifest['sourceHash'] = hash;
    manifest['crateVersion'] = readCrateVersion(native);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
  }
  out.writeln(hash);
  return 0;
}

String _slashed(String path) =>
    (Platform.isWindows ? path.replaceAll(r'\', '/') : path).replaceFirst(
      RegExp(r'/+$'),
      '',
    );

String _relative(String slashedRoot, File file) =>
    _slashed(file.path).substring(slashedRoot.length + 1);
