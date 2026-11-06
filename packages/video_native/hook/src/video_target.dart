/// Which targets the hook builds for, and the recipe's name for each.
library;

import 'package:code_assets/code_assets.dart';

/// The `TARGET` of `native/recipe/build.sh` that serves [os] on
/// [architecture]; null where no native library is built.
///
/// iOS builds arm64 for the device (`ios-arm64`) and for the Apple-silicon
/// simulator (`ios-sim-arm64`), told apart by [iosSdk]. The x86_64 simulator
/// is left out like Android x86_64: it gets the `missingLibrary` probe result.
///
/// Android x86_64 and armv7 are left out on purpose: the recipe builds
/// arm64-v8a only, and an emulator or a 32-bit phone gets the
/// `missingLibrary` probe result rather than a half-working decoder.
String? recipeTarget(OS os, Architecture architecture, {IOSSdk? iosSdk}) =>
    switch ((os, architecture, iosSdk)) {
      (OS.macOS, Architecture.arm64, _) => 'macos-arm64',
      (OS.android, Architecture.arm64, _) => 'android-arm64',
      (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS) => 'ios-arm64',
      (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator) => 'ios-sim-arm64',
      _ => null,
    };
