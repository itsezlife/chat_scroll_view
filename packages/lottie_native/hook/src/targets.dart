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
  const LottieNativeTarget(this.os, this.arch, {this.sdk});

  /// The target of a hook's code configuration.
  factory LottieNativeTarget.of(CodeConfig config) => LottieNativeTarget(
    config.targetOS,
    config.targetArchitecture,
    sdk: config.targetOS == OS.iOS ? config.iOS.targetSdk : null,
  );

  /// The operating system.
  final OS os;

  /// The CPU architecture.
  final Architecture arch;

  /// The iOS SDK (device or simulator); null elsewhere.
  final IOSSdk? sdk;

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

  /// The Rust target triple this host compiles for, or null when the hook
  /// does not build this target from source (yet): only macOS today.
  String? get rustTriple => switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    _ => null,
  };

  @override
  String toString() => '$os/$arch${sdk == null ? '' : '/${sdk!.type}'}';
}
