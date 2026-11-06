/// What `hook/build.dart` needs to compile the `native/` crate with cargo:
/// where cargo is, and what to say when it fails (the Rust target for a code
/// target is `LottieNativeTarget.rustTriple`).
///
/// Kept apart from the hook entry so the decisions are tested without
/// running a build.
library;

import 'dart:io';

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
