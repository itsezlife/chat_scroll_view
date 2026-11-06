/// What `hook/build.dart` needs to compile the `native/` crate with cargo:
/// where cargo is, how to run it for a target, and what to say when it fails
/// (the Rust target for a code target is `LottieNativeTarget.rustTriple`).
///
/// Kept apart from the hook entry so the decisions are tested without
/// running a build, and so the opt-in cross-compile test drives the same
/// function the hook does.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';

import 'android_ndk.dart';
import 'artifact_check.dart';
import 'build_environment.dart';
import 'delivery_plan.dart' show buildFromSourceEnvironment;
import 'targets.dart';

/// Compiles the crate in [crate] (the `native/` folder) for [target] into
/// [targetDir] and returns the library, after checking its header.
///
/// Builds on the running host. Throws [UnsupportedError] when it cannot
/// build [target],
/// [AndroidNdkUnavailable] when an Android build has no usable NDK (before
/// cargo starts), [ProcessException] when cargo fails, and [StateError] when
/// cargo succeeded but wrote a library for the wrong architecture or without
/// 16 KB alignment.
Future<File> compileCrate({
  required String cargo,
  required Uri crate,
  required Uri targetDir,
  required LottieNativeTarget target,
  required Map<String, String> environment,
}) async {
  final hostOs = OS.current;
  final triple = target.rustTriple;
  if (triple == null ||
      !target.buildableOn(
        hostOs: hostOs,
        hostArch: Architecture.current,
        environment: environment,
      )) {
    throw UnsupportedError(
      'lottie_native cannot compile its native library for $target from '
      'source on this host; unset build_from_source / '
      '$buildFromSourceEnvironment to use a prebuilt, if one is published.',
    );
  }
  final ndk = target.os == OS.android
      ? findAndroidNdk(environment: environment, hostOs: hostOs)
      : null;
  final arguments = [
    'build',
    '--release',
    '--locked',
    '--target',
    triple,
    '--target-dir',
    targetDir.toFilePath(),
    '--manifest-path',
    crate.resolve('Cargo.toml').toFilePath(),
  ];
  final result = await Process.run(
    cargo,
    arguments,
    environment: cargoBuildEnvironment(
      target: target,
      environment: environment,
      ndk: ndk,
    ),
  );
  if (result.exitCode != 0) {
    final output = '${result.stdout}\n${result.stderr}';
    final hint = missingTargetHint(output, triple);
    throw ProcessException(
      cargo,
      arguments,
      'cargo failed building the lottie_native crate '
      '(exit ${result.exitCode}). A first build needs network for the '
      'crates and the pinned tlottie commit.\n'
      '$output${hint == null ? '' : '\n$hint'}',
      result.exitCode,
    );
  }
  final library = File(
    targetDir.resolve('$triple/release/${target.libraryFileName}').toFilePath(),
  );
  final problem = artifactProblem(library.readAsBytesSync(), target);
  if (problem != null) {
    throw StateError('cargo built ${library.path} for $target, but $problem.');
  }
  return library;
}

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
