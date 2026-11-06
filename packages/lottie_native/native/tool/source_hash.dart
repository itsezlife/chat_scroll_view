/// Prints the hash of the crate sources; `--write` records it (and the crate
/// version) in `native/prebuilts.json`. Run from the package root:
///
/// ```sh
/// dart native/tool/source_hash.dart --write
/// ```
///
/// CI and a developer who edited the crate run it; the definition of the
/// hash lives in `hook/src/source_hash.dart`.
library;

import 'dart:io';

import '../../hook/src/source_hash.dart';

void main(List<String> args) {
  exitCode = runSourceHashTool(
    args,
    native: File.fromUri(Platform.script).parent.parent,
    out: stdout,
  );
}
