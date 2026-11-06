/// The build target the hook sees, as one small value: what the manifest
/// keys artifacts by and what cargo compiles for.
///
/// Kept apart from the hook entry so the mapping is tested without running a
/// build.
library;

import 'package:code_assets/code_assets.dart';

/// An operating system, a CPU architecture and, on iOS, a device or
/// simulator SDK.
final class LottieNativeTarget {
  /// Creates the target; [sdk] is only meaningful for [OS.iOS].
  const LottieNativeTarget(
    this.os,
    this.arch, {
    this.sdk,
    this.androidApi,
    this.iosVersion,
  });

  /// The target of a hook's code configuration.
  factory LottieNativeTarget.of(CodeConfig config) => LottieNativeTarget(
    config.targetOS,
    config.targetArchitecture,
    sdk: config.targetOS == OS.iOS ? config.iOS.targetSdk : null,
    androidApi: config.targetOS == OS.android
        ? config.android.targetNdkApi
        : null,
    iosVersion: config.targetOS == OS.iOS ? config.iOS.targetVersion : null,
  );

  /// The operating system.
  final OS os;

  /// The CPU architecture.
  final Architecture arch;

  /// The iOS SDK (device or simulator); null elsewhere.
  final IOSSdk? sdk;

  /// The Android API level the app targets; null elsewhere.
  final int? androidApi;

  /// The iOS deployment target (the major version, such as 13); null
  /// elsewhere.
  final int? iosVersion;

  /// The manifest key of this target, `<os>-<arch>[-simulator]`, or null when
  /// the manifest has no key for it (an unlisted combination).
  ///
  /// Spelled out instead of derived from the enums' names: the keys are a
  /// published vocabulary, and a rename in `code_assets` must not silently
  /// orphan every artifact.
  String? get key => switch ((os, arch, sdk)) {
    (OS.macOS, Architecture.arm64, _) => 'macos-arm64',
    (OS.macOS, Architecture.x64, _) => 'macos-x64',
    (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS) => 'ios-arm64',
    (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator) =>
      'ios-arm64-simulator',
    (OS.iOS, Architecture.x64, IOSSdk.iPhoneSimulator) => 'ios-x64-simulator',
    (OS.android, Architecture.arm64, _) => 'android-arm64',
    (OS.android, Architecture.x64, _) => 'android-x64',
    (OS.linux, Architecture.x64, _) => 'linux-x64',
    (OS.linux, Architecture.arm64, _) => 'linux-arm64',
    (OS.windows, Architecture.x64, _) => 'windows-x64',
    _ => null,
  };

  /// The Rust target triple, or null when ADR 042 ships no library for this
  /// target (Android 32-bit ARM, an iOS target without an SDK, any
  /// combination with no [key]).
  String? get rustTriple => switch (key) {
    'macos-arm64' => 'aarch64-apple-darwin',
    'macos-x64' => 'x86_64-apple-darwin',
    'ios-arm64' => 'aarch64-apple-ios',
    'ios-arm64-simulator' => 'aarch64-apple-ios-sim',
    'ios-x64-simulator' => 'x86_64-apple-ios',
    'android-arm64' => 'aarch64-linux-android',
    'android-x64' => 'x86_64-linux-android',
    'linux-x64' => 'x86_64-unknown-linux-gnu',
    'linux-arm64' => 'aarch64-unknown-linux-gnu',
    'windows-x64' => 'x86_64-pc-windows-msvc',
    _ => null,
  };

  /// The file cargo writes for the crate's `cdylib`.
  String get libraryFileName => switch (os) {
    OS.macOS || OS.iOS => 'libchat_lottie.dylib',
    OS.windows => 'chat_lottie.dll',
    _ => 'libchat_lottie.so',
  };

  /// Whether a build host running [hostOs] on [hostArch] can compile this
  /// target from source.
  ///
  /// Apple targets need the Apple SDK, so only a Mac. Android needs only
  /// the NDK, which ships for all three desktop hosts. Linux and Windows
  /// build natively; a Linux host of another architecture also works when
  /// the app has set cargo's linker for the triple in [environment]
  /// (`CARGO_TARGET_<TRIPLE>_LINKER`), because only the app knows its
  /// cross toolchain.
  bool buildableOn({
    required OS hostOs,
    required Architecture hostArch,
    Map<String, String> environment = const {},
  }) {
    final triple = rustTriple;
    if (triple == null) return false;
    return switch (os) {
      OS.macOS || OS.iOS => hostOs == OS.macOS,
      OS.android =>
        hostOs == OS.macOS || hostOs == OS.linux || hostOs == OS.windows,
      OS.linux =>
        hostOs == OS.linux &&
            (hostArch == arch ||
                environment.containsKey(cargoTargetVariable(triple, 'LINKER'))),
      OS.windows => hostOs == OS.windows,
      _ => false,
    };
  }

  @override
  String toString() => '$os/$arch${sdk == null ? '' : '/${sdk!.type}'}';
}

/// The per-triple cargo variable `CARGO_TARGET_<TRIPLE>_<name>` (for
/// example `LINKER`, `AR`): the triple upper-cased with `-` as `_`.
String cargoTargetVariable(String triple, String name) =>
    'CARGO_TARGET_${triple.toUpperCase().replaceAll('-', '_')}_$name';
