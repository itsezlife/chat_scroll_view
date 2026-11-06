/// What `hook/build.dart` needs to compile the `native/` crate with cargo:
/// the Rust target for a code target, and where cargo is.
///
/// Kept apart from the hook entry so the decisions are tested without
/// running a build.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'targets.dart';

/// The Rust target triple for [os] and [architecture], or null when this
/// slice does not build for it.
///
/// Only macOS is built from source in this slice. Another target gets no
/// asset rather than a failed build: a host that never registers the binding
/// (it probes first) still builds and runs, and the probe reports
/// [unsupportedTargetWarning]'s consequence at run time.
String? rustTargetFor(OS os, Architecture architecture) =>
    LottieNativeTarget(os, architecture).rustTriple;

/// The warning the hook logs when [rustTargetFor] has no answer.
String unsupportedTargetWarning(OS os, Architecture architecture) =>
    'lottie_native builds its native library from source on macOS (arm64 and '
    'x86_64) only; this build targets $os/$architecture, so no library is '
    'bundled and it is unavailable at run time (NativeLottieBinding.probe() '
    'reports missingLibrary). Android, iOS, Windows and Linux arrive with '
    'slice 6: hash-pinned prebuilt libraries and an opt-in flag to compile '
    'from source.';

/// A line to append to a failed cargo run's message when [output] says the
/// Rust standard library for [target] is not installed, else null.
String? missingTargetHint(String output, String target) =>
    output.contains("can't find crate for") ||
        output.contains('target may not be installed')
    ? 'rustup target add $target'
    : null;

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
