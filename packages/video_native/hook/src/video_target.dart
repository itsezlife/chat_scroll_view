/// Which targets the hook builds for, and the recipe's name for each.
library;

import 'package:code_assets/code_assets.dart';

/// The `TARGET` of `native/recipe/build.sh` that serves [os] on
/// [architecture]; null where no native library is built.
///
/// Android x86_64 and armv7 are left out on purpose: the recipe builds
/// arm64-v8a only, and an emulator or a 32-bit phone gets the
/// `missingLibrary` probe result rather than a half-working decoder.
String? recipeTarget(OS os, Architecture architecture) =>
    switch ((os, architecture)) {
      (OS.macOS, Architecture.arm64) => 'macos-arm64',
      (OS.android, Architecture.arm64) => 'android-arm64',
      _ => null,
    };
