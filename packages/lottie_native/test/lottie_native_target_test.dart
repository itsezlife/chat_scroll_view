import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/targets.dart';

void main() {
  group('LottieNativeTarget.key', () {
    // The keys are the manifest's vocabulary: a change here silently orphans
    // every published artifact, so each is spelled out.
    final cases = <(LottieNativeTarget, String)>[
      (LottieNativeTarget(OS.macOS, Architecture.arm64), 'macos-arm64'),
      (LottieNativeTarget(OS.macOS, Architecture.x64), 'macos-x64'),
      (
        LottieNativeTarget(OS.iOS, Architecture.arm64, sdk: IOSSdk.iPhoneOS),
        'ios-arm64',
      ),
      (
        LottieNativeTarget(
          OS.iOS,
          Architecture.arm64,
          sdk: IOSSdk.iPhoneSimulator,
        ),
        'ios-arm64-simulator',
      ),
      (
        LottieNativeTarget(
          OS.iOS,
          Architecture.x64,
          sdk: IOSSdk.iPhoneSimulator,
        ),
        'ios-x64-simulator',
      ),
      (LottieNativeTarget(OS.android, Architecture.arm64), 'android-arm64'),
      (LottieNativeTarget(OS.android, Architecture.x64), 'android-x64'),
      (LottieNativeTarget(OS.linux, Architecture.x64), 'linux-x64'),
      (LottieNativeTarget(OS.linux, Architecture.arm64), 'linux-arm64'),
      (LottieNativeTarget(OS.windows, Architecture.x64), 'windows-x64'),
    ];

    for (final (target, key) in cases) {
      test('is $key', () {
        expect(target.key, key);
      });
    }

    test('is null for a target the manifest has no key for', () {
      expect(LottieNativeTarget(OS.linux, Architecture.ia32).key, isNull);
      expect(LottieNativeTarget(OS.iOS, Architecture.arm64).key, isNull);
    });
  });

  group('LottieNativeTarget.rustTriple', () {
    test('maps macOS arm64 and x64 to their Apple triples', () {
      expect(
        LottieNativeTarget(OS.macOS, Architecture.arm64).rustTriple,
        'aarch64-apple-darwin',
      );
      expect(
        LottieNativeTarget(OS.macOS, Architecture.x64).rustTriple,
        'x86_64-apple-darwin',
      );
    });

    test('is null for every target this host cannot build yet', () {
      expect(LottieNativeTarget(OS.linux, Architecture.x64).rustTriple, isNull);
      expect(
        LottieNativeTarget(OS.macOS, Architecture.ia32).rustTriple,
        isNull,
      );
    });
  });

  group('LottieNativeTarget.toString', () {
    test('names os, architecture and sdk for a log line', () {
      expect(
        LottieNativeTarget(
          OS.iOS,
          Architecture.x64,
          sdk: IOSSdk.iPhoneSimulator,
        ).toString(),
        allOf(contains('ios'), contains('x64'), contains('iphonesimulator')),
      );
    });
  });
}
