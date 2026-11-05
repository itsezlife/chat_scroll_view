/// What `hook/build.dart` needs to compile the `native/` crate with cargo:
/// the Rust target for a code target, and where cargo is.
///
/// Kept apart from the hook entry so the decisions are tested without
/// running a build.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// The Rust target triple for [os] and [architecture].
///
/// Only macOS is built from source in this slice. Every other target throws,
/// naming what lands later, so a host on Linux or Android reads the plan
/// instead of a linker error.
String rustTargetFor(OS os, Architecture architecture) {
  if (os == OS.macOS) {
    if (architecture == Architecture.arm64) return 'aarch64-apple-darwin';
    if (architecture == Architecture.x64) return 'x86_64-apple-darwin';
  }
  throw UnsupportedError(
    'lottie_native builds its native library from source on macOS (arm64 and '
    'x86_64) only; this build targets $os/$architecture. Android, iOS, '
    'Windows and Linux arrive with slice 6: hash-pinned prebuilt libraries '
    'and an opt-in flag to compile from source.',
  );
}

/// Thrown when no `cargo` executable can be found.
final class CargoNotFound implements Exception {
  /// Creates the failure for the places [searched].
  const CargoNotFound(this.searched);

  /// Every path that was tried, in order.
  final List<String> searched;

  @override
  String toString() =>
      'cargo was not found, and lottie_native compiles its native renderer '
      'with it. Install Rust with rustup (https://rustup.rs) and make sure '
      'cargo is on PATH (rustup adds ~/.cargo/bin to your shell profile), '
      'then build again. Searched: ${searched.join(', ')}.';
}

/// Finds `cargo`: first on `PATH`, then under `CARGO_HOME/bin`, then in
/// `~/.cargo/bin`.
///
/// The fallbacks exist because a build hook runs in a trimmed environment,
/// and an IDE-launched Flutter often misses the shell profile that rustup
/// edits. [environment] and [fileExists] are parameters so the order is
/// tested without a Rust install.
String findCargo({
  required Map<String, String> environment,
  bool Function(String path)? fileExists,
}) {
  final exists = fileExists ?? (path) => File(path).existsSync();
  final separator = Platform.isWindows ? ';' : ':';
  final name = Platform.isWindows ? 'cargo.exe' : 'cargo';

  final candidates = <String>[
    for (final dir in (environment['PATH'] ?? '').split(separator))
      if (dir.isNotEmpty) '$dir/$name',
    if (environment['CARGO_HOME'] case final home?) '$home/bin/$name',
    if (environment['HOME'] case final home?) '$home/.cargo/bin/$name',
  ];
  for (final candidate in candidates) {
    if (exists(candidate)) return candidate;
  }
  throw CargoNotFound(candidates);
}
