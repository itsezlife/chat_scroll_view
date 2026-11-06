/// The files whose change must re-run the hook.
///
/// A directory dependency only notices files added or removed, not an
/// existing file edited, so the crate used to be edited with the hook not
/// re-running and stale native code shipping. Every input is therefore
/// declared as a file, enumerated when the hook runs (so a file added later
/// is picked up by that run).
library;

import 'dart:io';

import 'source_hash.dart';

/// Every file the build reads, as file URIs: the crate sources
/// (`crateSourceFiles`), the manifest, and the hook's own Dart sources.
///
/// [packageRoot] is the package's root directory URI.
List<Uri> rebuildInputs(Uri packageRoot) {
  final root = Directory.fromUri(packageRoot);
  final manifest = File.fromUri(packageRoot.resolve('native/prebuilts.json'));
  final hook = Directory.fromUri(packageRoot.resolve('hook/'));
  return [
    for (final file in crateSourceFiles(
      Directory.fromUri(root.uri.resolve('native/')),
    ))
      file.uri,
    if (manifest.existsSync()) manifest.uri,
    if (hook.existsSync())
      for (final entity in hook.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) entity.uri,
  ];
}
