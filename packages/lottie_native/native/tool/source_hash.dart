/// Prints the hash of the crate sources; `--write` records it (and the crate
/// version) in `native/prebuilts.json`; `--check` fails when the recorded hash
/// is stale. Run from the package root:
///
/// ```sh
/// dart native/tool/source_hash.dart --write
/// dart native/tool/source_hash.dart --check
/// ```
///
/// CI and a developer who edited the crate run it; the definition of the
/// hash lives in `hook/src/source_hash.dart`. In short: SHA-256 over the line
/// `lottie-native-source-v2` and then, for every source file sorted by path,
/// `<byte length of path>:<path><byte length of content>:<content>` (ASCII
/// decimal lengths), so no path can imitate the framing of its neighbour; a
/// path with a control character is an error.
library;

import 'dart:convert';
import 'dart:io';

import '../../hook/src/source_hash.dart';

void main(List<String> args) {
  exitCode = runSourceHashCommand(
    args,
    native: File.fromUri(Platform.script).parent.parent,
    out: stdout,
  );
}

/// The command line of this tool: `--check` here, everything else in
/// [runSourceHashTool]. Returns the exit code.
///
/// `--check` lives beside the entry point and not next to the hash because it
/// is only a gate for CI: it needs no part of the hash's definition that the
/// hook does not already share.
int runSourceHashCommand(
  List<String> args, {
  required Directory native,
  required StringSink out,
}) {
  if (!args.contains('--check')) {
    return runSourceHashTool(args, native: native, out: out);
  }
  if (args.length != 1) {
    out.writeln('usage: dart native/tool/source_hash.dart --check');
    return 64;
  }
  return _check(native, out);
}

/// Fails when `prebuilts.json` records a non-empty `sourceHash` that is not
/// the hash of the sources: published artifacts that no longer match the crate
/// must be refreshed (`--write` after new libraries) or dropped on purpose
/// (empty `sourceHash`, no artifacts), never left to disagree silently.
int _check(Directory native, StringSink out) {
  final file = File('${native.path}/prebuilts.json');
  final Object? recorded;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('not a JSON object');
    }
    recorded = decoded['sourceHash'] ?? '';
  } on FileSystemException catch (e) {
    out.writeln('cannot read ${file.path}: ${e.message}');
    return 1;
  } on FormatException catch (e) {
    out.writeln('${file.path} is not a manifest: ${e.message}');
    return 1;
  }
  if (recorded is! String) {
    out.writeln('${file.path} "sourceHash" must be a string');
    return 1;
  }
  if (recorded.isEmpty) {
    out.writeln('sourceHash is empty: no prebuilt is published');
    return 0;
  }
  final current = computeSourceHash(native);
  if (recorded == current) {
    out.writeln('sourceHash is current: $current');
    return 0;
  }
  out.writeln(
    'prebuilts.json records sourceHash $recorded but the sources hash to '
    '$current.\n'
    'The crate changed after the prebuilts were built. Publish new libraries '
    'and run `dart native/tool/source_hash.dart --write`, or set sourceHash '
    'to "" and clear artifacts to withdraw them on purpose.',
  );
  return 1;
}
