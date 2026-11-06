/// Delivers the native library as the code asset that
/// `lib/src/native/chat_lottie_symbols.dart` binds to.
///
/// In order (see `src/delivery_plan.dart`): compile `native/` with cargo when
/// the app asks for it, else download the hash-pinned prebuilt listed in
/// `native/prebuilts.json`, else compile if this host can, else bundle
/// nothing and warn. A first source build needs network for the crates and
/// the pinned tlottie commit.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'src/cargo_build.dart';
import 'src/delivery_plan.dart';
import 'src/prebuilt_download.dart';
import 'src/prebuilt_manifest.dart';
import 'src/rebuild_inputs.dart';
import 'src/source_hash.dart';
import 'src/targets.dart';

/// Names the asset `package:lottie_native/src/native/chat_lottie_symbols.dart`,
/// the library URI of the file whose `@Native` functions resolve against it.
const _assetName = 'src/native/chat_lottie_symbols.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final target = LottieNativeTarget.of(input.config.code);
    final native = Directory.fromUri(input.packageRoot.resolve('native/'));

    // Every input as a file: a directory would miss an edit to a file in it.
    output.dependencies.addAll(rebuildInputs(input.packageRoot));

    CargoNotFound? noCargo;
    String? cargo;
    try {
      cargo = findCargo(environment: Platform.environment);
    } on CargoNotFound catch (e) {
      noCargo = e;
    }

    final steps = planDelivery(
      buildFromSource: wantsBuildFromSource(
        userDefine: input.userDefines['build_from_source'],
        environment: Platform.environment,
      ),
      match: matchPrebuilt(
        manifest: _readManifest(native),
        sourceHash: computeSourceHash(native),
        target: target,
      ),
      hasCargo: cargo != null,
      target: target,
    );

    for (final step in steps) {
      final library = switch (step) {
        UsePrebuilt(:final artifact, :final url) => await _download(
          input,
          artifact,
          url,
        ),
        CompileFromSource() => await _compile(
          input,
          target,
          cargo ?? (throw noCargo!),
        ),
        // No asset: the build succeeds and the probe finds no library.
        NoLibrary(:final reason) => _warn(reason),
      };
      if (library == null) continue;
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: _assetName,
          linkMode: DynamicLoadingBundled(),
          file: library,
        ),
      );
      return;
    }
  });
}

/// The manifest, or null when it is absent or unreadable: a broken manifest
/// is a warning, never a failed build.
PrebuiltManifest? _readManifest(Directory native) {
  final file = File('${native.path}/prebuilts.json');
  if (!file.existsSync()) return null;
  try {
    return PrebuiltManifest.parse(file.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('warning: lottie_native ignores native/prebuilts.json: $e');
    return null;
  }
}

Future<Uri?> _download(
  BuildInput input,
  PrebuiltArtifact artifact,
  Uri url,
) async {
  // The shared directory outlives this build and is the same for every
  // consumer of the package, so a library is downloaded once.
  final result = await fetchPrebuilt(
    artifact: artifact,
    url: url,
    cacheDir: Directory.fromUri(
      input.outputDirectoryShared.resolve('lottie_native_prebuilts/'),
    ),
  );
  switch (result) {
    case PrebuiltReady(:final file):
      return file.uri;
    case PrebuiltUnavailable(:final reason):
      stdout.writeln('lottie_native: prebuilt library not used: $reason');
      return null;
  }
}

Future<Uri?> _compile(
  BuildInput input,
  LottieNativeTarget target,
  String cargo,
) async {
  final triple = target.rustTriple;
  if (triple == null) {
    throw UnsupportedError(
      'lottie_native cannot compile its native library for $target from '
      'source yet; unset build_from_source / '
      '$buildFromSourceEnvironment to use a prebuilt, if one is published.',
    );
  }
  final crate = input.packageRoot.resolve('native/');
  final targetDir = input.outputDirectory.resolve('cargo/');
  final result = await Process.run(cargo, [
    'build',
    '--release',
    '--locked',
    '--target',
    triple,
    '--target-dir',
    targetDir.toFilePath(),
    '--manifest-path',
    crate.resolve('Cargo.toml').toFilePath(),
  ]);
  if (result.exitCode != 0) {
    final output = '${result.stdout}\n${result.stderr}';
    final hint = missingTargetHint(output, triple);
    throw ProcessException(
      cargo,
      ['build', '--release', '--target', triple],
      'cargo failed building the lottie_native crate '
      '(exit ${result.exitCode}). A first build needs network for the '
      'crates and the pinned tlottie commit.\n'
      '$output${hint == null ? '' : '\n$hint'}',
      result.exitCode,
    );
  }
  return targetDir.resolve('$triple/release/libchat_lottie.dylib');
}

Uri? _warn(String reason) {
  stderr.writeln('warning: $reason');
  return null;
}
