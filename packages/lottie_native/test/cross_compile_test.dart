/// Real cross-compiles of the `native/` crate through the hook's own build
/// function. Compile only: nothing is installed, launched or run, and no
/// emulator, simulator or device is touched; the artifact is inspected as
/// bytes.
///
/// Skipped unless `LOTTIE_NATIVE_CROSS=1`, because each target is a release
/// build with LTO (minutes) and needs network on the first run for the
/// crates and the pinned tlottie commit. A target is also skipped when this
/// host cannot build it, its Rust target is not installed (`rustup target
/// add TRIPLE`; nothing is installed here) or, for Android, no NDK exists.
@Tags(['native-cross'])
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/android_ndk.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/artifact_check.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/cargo_build.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/targets.dart';

const _targets = <LottieNativeTarget>[
  LottieNativeTarget(OS.macOS, Architecture.arm64),
  LottieNativeTarget(OS.macOS, Architecture.x64),
  LottieNativeTarget(OS.iOS, Architecture.arm64, sdk: IOSSdk.iPhoneOS),
  LottieNativeTarget(OS.iOS, Architecture.arm64, sdk: IOSSdk.iPhoneSimulator),
  LottieNativeTarget(OS.iOS, Architecture.x64, sdk: IOSSdk.iPhoneSimulator),
  LottieNativeTarget(OS.android, Architecture.arm64, androidApi: 24),
  LottieNativeTarget(OS.android, Architecture.x64, androidApi: 24),
];

/// Why [target] cannot be built here, or null.
String? _whyNot(LottieNativeTarget target, String cargo) {
  final environment = Platform.environment;
  if (!target.buildableOn(
    hostOs: OS.current,
    hostArch: Architecture.current,
    environment: environment,
  )) {
    return 'this host cannot build $target';
  }
  final sysroot = Process.runSync(
    cargo.replaceFirst(RegExp(r'cargo$'), 'rustc'),
    ['--print', 'sysroot'],
  ).stdout.toString().trim();
  final triple = target.rustTriple!;
  if (!Directory('$sysroot/lib/rustlib/$triple').existsSync()) {
    return 'Rust target $triple is not installed (rustup target add $triple)';
  }
  if (target.os == OS.android) {
    try {
      findAndroidNdk(environment: environment, hostOs: OS.current);
    } on AndroidNdkUnavailable catch (e) {
      return e.toString();
    }
  }
  return null;
}

void main() {
  final enabled = Platform.environment['LOTTIE_NATIVE_CROSS'] == '1';
  late final String cargo;
  late final Directory targetDir;

  setUpAll(() {
    if (!enabled) return;
    cargo = findCargo(environment: Platform.environment);
    targetDir = Directory.systemTemp.createTempSync('lottie_native_cross');
  });
  tearDownAll(() {
    if (enabled) targetDir.deleteSync(recursive: true);
  });

  group('cross-compile (LOTTIE_NATIVE_CROSS=1)', () {
    for (final target in _targets) {
      test(
        '${target.key} builds and passes the post-build check',
        () async {
          final why = _whyNot(target, cargo);
          if (why != null) {
            markTestSkipped(why);
            return;
          }

          final library = await compileCrate(
            cargo: cargo,
            crate: Directory('native').absolute.uri,
            targetDir: targetDir.uri,
            target: target,
            environment: Platform.environment,
          );

          expect(library.existsSync(), isTrue);
          expect(artifactProblem(library.readAsBytesSync(), target), isNull);
          // Printed so the run can be audited against the tool-side checks.
          // ignore: avoid_print
          print('${target.key}: ${library.path} (${library.lengthSync()} B)');
        },
        skip: enabled ? false : 'set LOTTIE_NATIVE_CROSS=1 to cross-compile',
        timeout: const Timeout(Duration(minutes: 30)),
      );
    }
  });
}
