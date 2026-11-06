/// The fingerprint of the crate sources, which ties a prebuilt library to the
/// code it was built from.
///
/// The hash is SHA-256 over this canonical listing: the version line
/// `lottie-native-source-v2` and LF, then for each file `Cargo.toml`,
/// `Cargo.lock`, everything under `include/` and everything under `src/` (all
/// relative to `native/`), sorted by their `/`-separated relative path
/// (string order), one record
///
/// ```text
/// <byte length of the path>:<path><byte length of the content>:<content>
/// ```
///
/// Both lengths are ASCII decimal and count bytes (the path as UTF-8), and
/// nothing else separates the fields. Because every field announces its own
/// length, no path or content can imitate the framing of the next record, so
/// two different trees never produce the same listing. (The first framing,
/// `path LF length LF bytes LF`, let a path containing LF swallow its
/// neighbour; `v2` replaces it.) A path with a control character is refused
/// outright: it has no business in a crate. Bytes are hashed as stored: a
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
  // Resolved against the directory's URI, which always ends with a slash:
  // joining a path string would give "native//src" for a trailing slash.
  final files = <File>[
    for (final name in const ['Cargo.toml', 'Cargo.lock'])
      File.fromUri(native.uri.resolve(name)),
    for (final dir in const ['include/', 'src/'])
      if (Directory.fromUri(native.uri.resolve(dir)).existsSync())
        ...Directory.fromUri(
          native.uri.resolve(dir),
        ).listSync(recursive: true).whereType<File>(),
  ];
  return files
    ..sort((a, b) => _relative(root, a).compareTo(_relative(root, b)));
}

/// One record of the listing: a file's relative path and its bytes.
typedef SourceRecord = ({String path, List<int> bytes});

/// The version line the listing starts with; a change of format changes it.
const _listingVersion = 'lottie-native-source-v2';

/// The hex SHA-256 of the listing of [records], which must already be sorted
/// (see the format above).
String hashSourceListing(Iterable<SourceRecord> records) {
  // The sources are a few hundred kilobytes: one buffer, no streaming.
  final listing = BytesBuilder(copy: false)
    ..add(utf8.encode('$_listingVersion\n'));
  for (final (:path, :bytes) in records) {
    final name = utf8.encode(path);
    listing
      ..add(utf8.encode('${name.length}:'))
      ..add(name)
      ..add(utf8.encode('${bytes.length}:'))
      ..add(bytes);
  }
  return sha256.convert(listing.takeBytes()).toString();
}

/// The hex SHA-256 of [native]'s sources, as documented above.
///
/// Throws [FormatException] for a source path with a control character.
String computeSourceHash(Directory native) {
  final root = _slashed(native.path);
  return hashSourceListing([
    for (final file in crateSourceFiles(native))
      (
        path: _checkedPath(_relative(root, file)),
        bytes: file.readAsBytesSync(),
      ),
  ]);
}

String _checkedPath(String path) {
  if (path.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw FormatException(
      'a crate source path has a control character: ${jsonEncode(path)}',
    );
  }
  return path;
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
