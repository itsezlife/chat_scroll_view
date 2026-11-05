/// Builds the `native/` crate with cargo and registers the library as the
/// code asset that `lib/src/native/chat_lottie_symbols.dart` binds to.
///
/// macOS only for now; see [rustTargetFor] (another target gets no asset). A first build needs network for
/// the crates and the pinned tlottie commit.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'src/cargo_build.dart';

/// Names the asset `package:lottie_native/src/native/chat_lottie_symbols.dart`,
/// the library URI of the file whose `@Native` functions resolve against it.
const _assetName = 'src/native/chat_lottie_symbols.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = rustTargetFor(code.targetOS, code.targetArchitecture);
    if (target == null) {
      // No asset: the build succeeds and the probe finds no library.
      stderr.writeln(
        'warning: ${unsupportedTargetWarning(code.targetOS, code.targetArchitecture)}',
      );
      return;
    }
    final cargo = findCargo(environment: Platform.environment);

    final crate = input.packageRoot.resolve('native/');
    final targetDir = input.outputDirectory.resolve('cargo/');
    final result = await Process.run(cargo, [
      'build',
      '--release',
      '--locked',
      '--target',
      target,
      '--target-dir',
      targetDir.toFilePath(),
      '--manifest-path',
      crate.resolve('Cargo.toml').toFilePath(),
    ]);
    if (result.exitCode != 0) {
      final output = '${result.stdout}\n${result.stderr}';
      final hint = missingTargetHint(output, target);
      throw ProcessException(
        cargo,
        ['build', '--release', '--target', target],
        'cargo failed building the lottie_native crate '
        '(exit ${result.exitCode}). A first build needs network for the '
        'crates and the pinned tlottie commit.\n'
        '$output${hint == null ? '' : '\n$hint'}',
        result.exitCode,
      );
    }

    final library = targetDir.resolve('$target/release/libchat_lottie.dylib');
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );

    // Edits to the crate re-run the hook.
    output.dependencies
      ..add(crate.resolve('Cargo.toml'))
      ..add(crate.resolve('Cargo.lock'))
      ..add(crate.resolve('src/'))
      ..add(crate.resolve('include/chat_lottie.h'));
  });
}
