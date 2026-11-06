/// Finding the Android NDK and its clang wrappers: what the wrapper's compile needs to link
/// a `.so` for Android.
///
/// Kept apart from the hook entry so the discovery rules are tested over a
/// fake file system, without an NDK installed.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// The two questions discovery asks the file system.
final class NdkFiles {
  /// Creates the view over the given functions.
  const NdkFiles({required this.isDirectory, required this.list});

  /// The real disk.
  static final NdkFiles disk = NdkFiles(
    isDirectory: (path) => Directory(path).existsSync(),
    list: (path) {
      final directory = Directory(path);
      if (!directory.existsSync()) return const [];
      return [
        for (final entry in directory.listSync(followLinks: false))
          entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
      ];
    },
  );

  /// Whether [path] is a directory.
  final bool Function(String path) isDirectory;

  /// The names directly inside [path]; empty when it is not a directory.
  final List<String> Function(String path) list;
}

/// Thrown when no usable NDK exists. The message says what to install and
/// where the hook looked; the hook turns it into the no-asset path.
final class AndroidNdkUnavailable implements Exception {
  /// Creates the failure with the full [message].
  const AndroidNdkUnavailable(this.message);

  /// What went wrong and what to do.
  final String message;

  @override
  String toString() => message;
}

/// One installed NDK: its folder and the host-specific toolchain inside.
final class AndroidNdk {
  const AndroidNdk._(this.root, this._bin, this._files, this._windows);

  /// The NDK folder, such as `<sdk>/ndk/28.2.13676358`.
  final String root;

  final String _bin;
  final NdkFiles _files;
  final bool _windows;

  /// The archiver.
  String get ar => '$_bin/llvm-ar${_windows ? '.exe' : ''}';

  /// The clang wrapper that links for [triple] (such as
  /// `aarch64-linux-android`) at the API level the NDK offers closest to
  /// [api].
  ///
  /// The NDK ships one wrapper per level, and it fixes the minimum API the
  /// library may call. An app asking for less than the NDK's lowest gets the
  /// lowest (older levels no longer exist there); one asking for a level the
  /// NDK lacks gets the nearest below it, or the highest when it asks for
  /// more than any.
  String linker(String triple, int api) {
    final suffix = _windows ? '.cmd' : '';
    final pattern = RegExp(
      '^${RegExp.escape(triple)}(\\d+)-clang${RegExp.escape(suffix)}\$',
    );
    final levels = <int>[
      for (final name in _files.list(_bin))
        if (pattern.firstMatch(name) case final match?)
          int.parse(match.group(1)!),
    ]..sort();
    if (levels.isEmpty) {
      throw AndroidNdkUnavailable(
        'The Android NDK at $root has no $triple clang wrappers under '
        '$_bin. Install a complete NDK (Android Studio, SDK Manager, '
        'SDK Tools, "NDK (Side by side)").',
      );
    }
    final level = levels.lastWhere((l) => l <= api, orElse: () => levels.first);
    return '$_bin/$triple$level-clang$suffix';
  }
}

/// Finds the NDK: `ANDROID_NDK_HOME`, then `ANDROID_NDK_ROOT`, then the
/// highest version under `<sdk>/ndk`, where `<sdk>` is `ANDROID_HOME`, else
/// `ANDROID_SDK_ROOT`, else the Android Studio default of [hostOs].
///
/// A candidate counts only when it holds the toolchain of this host, so a
/// half-installed version is skipped rather than chosen because it sorts
/// highest. Versions are compared as numbers: `100` is above `28`.
AndroidNdk findAndroidNdk({
  required Map<String, String> environment,
  required OS hostOs,
  NdkFiles? files,
}) {
  final disk = files ?? NdkFiles.disk;
  final windows = hostOs == OS.windows;
  final tag = switch (hostOs) {
    OS.linux => 'linux-x86_64',
    OS.windows => 'windows-x86_64',
    _ => 'darwin-x86_64',
  };
  String binOf(String root) => '$root/toolchains/llvm/prebuilt/$tag/bin';
  AndroidNdk? candidate(String root) => disk.isDirectory(binOf(root))
      ? AndroidNdk._(root, binOf(root), disk, windows)
      : null;

  final searched = <String>[];
  for (final variable in const ['ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT']) {
    final root = environment[variable];
    if (root == null || root.isEmpty) continue;
    if (candidate(root) case final ndk?) return ndk;
    searched.add('$variable=$root (no toolchains/llvm/prebuilt/$tag)');
  }

  final sdk = _sdkFolder(environment, hostOs);
  if (sdk != null) {
    final versions = <(List<int>, String)>[
      for (final name in disk.list('$sdk/ndk'))
        if (RegExp(r'^\d+(\.\d+)*$').hasMatch(name))
          ([for (final part in name.split('.')) int.parse(part)], name),
    ]..sort((a, b) => _compare(b.$1, a.$1));
    for (final (_, name) in versions) {
      if (candidate('$sdk/ndk/$name') case final ndk?) return ndk;
    }
    searched.add('$sdk/ndk (no complete NDK version)');
  }

  throw AndroidNdkUnavailable(
    'The Android NDK was not found, and video_native needs it to compile '
    'its native video library for Android. Install it with Android Studio '
    '(SDK Manager, SDK Tools, "NDK (Side by side)") or '
    '`sdkmanager "ndk;28.2.13676358"`, or set ANDROID_NDK_HOME. Searched: '
    '${searched.isEmpty ? 'nothing (set ANDROID_NDK_HOME or ANDROID_HOME)' : searched.join('; ')}.',
  );
}

String? _sdkFolder(Map<String, String> environment, OS hostOs) {
  for (final variable in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final value = environment[variable];
    if (value != null && value.isNotEmpty) return value;
  }
  return switch (hostOs) {
    OS.macOS => _under(environment['HOME'], 'Library/Android/sdk'),
    OS.linux => _under(environment['HOME'], 'Android/Sdk'),
    OS.windows => _under(environment['LOCALAPPDATA'], 'Android/Sdk'),
    _ => null,
  };
}

String? _under(String? base, String path) =>
    base == null || base.isEmpty ? null : '$base/$path';

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
