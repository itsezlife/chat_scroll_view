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
      (const LottieNativeTarget(OS.macOS, Architecture.arm64), 'macos-arm64'),
      (const LottieNativeTarget(OS.macOS, Architecture.x64), 'macos-x64'),
      (
        const LottieNativeTarget(
          OS.iOS,
          Architecture.arm64,
          sdk: IOSSdk.iPhoneOS,
        ),
        'ios-arm64',
      ),
      (
        const LottieNativeTarget(
          OS.iOS,
          Architecture.arm64,
          sdk: IOSSdk.iPhoneSimulator,
        ),
        'ios-arm64-simulator',
      ),
      (
        const LottieNativeTarget(
          OS.iOS,
          Architecture.x64,
          sdk: IOSSdk.iPhoneSimulator,
        ),
        'ios-x64-simulator',
      ),
      (
        const LottieNativeTarget(OS.android, Architecture.arm64),
        'android-arm64',
      ),
      (const LottieNativeTarget(OS.android, Architecture.x64), 'android-x64'),
      (const LottieNativeTarget(OS.linux, Architecture.x64), 'linux-x64'),
      (const LottieNativeTarget(OS.linux, Architecture.arm64), 'linux-arm64'),
      (const LottieNativeTarget(OS.windows, Architecture.x64), 'windows-x64'),
    ];

    for (final (target, key) in cases) {
      test('is $key', () {
        expect(target.key, key);
      });
    }

    for (final (target, key) in cases) {
      test('$key names its target back', () {
        final back = LottieNativeTarget.fromKey(key);
        expect(back, isNotNull);
        expect(
          (back!.os, back.arch, back.sdk),
          (target.os, target.arch, target.sdk),
        );
        expect(back.key, key);
      });
    }

    test('fromKey knows exactly the published keys, in a stable order', () {
      expect(LottieNativeTarget.keys, [for (final (_, key) in cases) key]);
      expect(LottieNativeTarget.fromKey('plan9-x64'), isNull);
    });

    test('is null for a target the manifest has no key for', () {
      expect(const LottieNativeTarget(OS.linux, Architecture.ia32).key, isNull);
      expect(const LottieNativeTarget(OS.iOS, Architecture.arm64).key, isNull);
    });
  });

  group('LottieNativeTarget.rustTriple', () {
    const ios = LottieNativeTarget(
      OS.iOS,
      Architecture.arm64,
      sdk: IOSSdk.iPhoneOS,
    );
    const iosSim = LottieNativeTarget(
      OS.iOS,
      Architecture.arm64,
      sdk: IOSSdk.iPhoneSimulator,
    );
    const iosX64Sim = LottieNativeTarget(
      OS.iOS,
      Architecture.x64,
      sdk: IOSSdk.iPhoneSimulator,
    );
    // Each triple is spelled out: cargo and rustup know these names, and a
    // typo only shows up as a failed build on that one target.
    final cases = <(LottieNativeTarget, String)>[
      (
        const LottieNativeTarget(OS.macOS, Architecture.arm64),
        'aarch64-apple-darwin',
      ),
      (
        const LottieNativeTarget(OS.macOS, Architecture.x64),
        'x86_64-apple-darwin',
      ),
      (ios, 'aarch64-apple-ios'),
      (iosSim, 'aarch64-apple-ios-sim'),
      (iosX64Sim, 'x86_64-apple-ios'),
      (
        const LottieNativeTarget(OS.android, Architecture.arm64),
        'aarch64-linux-android',
      ),
      (
        const LottieNativeTarget(OS.android, Architecture.x64),
        'x86_64-linux-android',
      ),
      (
        const LottieNativeTarget(OS.linux, Architecture.x64),
        'x86_64-unknown-linux-gnu',
      ),
      (
        const LottieNativeTarget(OS.linux, Architecture.arm64),
        'aarch64-unknown-linux-gnu',
      ),
      (
        const LottieNativeTarget(OS.windows, Architecture.x64),
        'x86_64-pc-windows-msvc',
      ),
    ];
    for (final (target, triple) in cases) {
      test('${target.key} is $triple', () {
        expect(target.rustTriple, triple);
      });
    }

    test('is null where ADR 042 ships no library', () {
      // Android 32-bit ARM is not supported; neither is an iOS target
      // without an SDK, nor an architecture with no key.
      expect(
        const LottieNativeTarget(OS.android, Architecture.arm).rustTriple,
        isNull,
      );
      expect(
        const LottieNativeTarget(OS.iOS, Architecture.arm64).rustTriple,
        isNull,
      );
      expect(
        const LottieNativeTarget(OS.macOS, Architecture.ia32).rustTriple,
        isNull,
      );
    });
  });

  group('LottieNativeTarget.libraryFileName', () {
    test('is the platform shape of the crate name', () {
      String name(OS os, [IOSSdk? sdk]) =>
          LottieNativeTarget(os, Architecture.arm64, sdk: sdk).libraryFileName;
      expect(name(OS.macOS), 'libchat_lottie.dylib');
      expect(name(OS.iOS, IOSSdk.iPhoneOS), 'libchat_lottie.dylib');
      expect(name(OS.android), 'libchat_lottie.so');
      expect(name(OS.linux), 'libchat_lottie.so');
      expect(name(OS.windows), 'chat_lottie.dll');
    });
  });

  group('LottieNativeTarget.buildableOn', () {
    // Rows: the target; columns: the host OS. The rule: Apple targets need
    // a Mac (the SDK), Android needs only the NDK, Linux and Windows build
    // natively.
    const mac = LottieNativeTarget(OS.macOS, Architecture.arm64);
    const ios = LottieNativeTarget(
      OS.iOS,
      Architecture.arm64,
      sdk: IOSSdk.iPhoneOS,
    );
    const android = LottieNativeTarget(OS.android, Architecture.arm64);
    const linuxX64 = LottieNativeTarget(OS.linux, Architecture.x64);
    const linuxArm = LottieNativeTarget(OS.linux, Architecture.arm64);
    const windows = LottieNativeTarget(OS.windows, Architecture.x64);

    final table = <String, (LottieNativeTarget, OS, Architecture, bool)>{
      'macOS from a Mac': (mac, OS.macOS, Architecture.arm64, true),
      'macOS from Linux': (mac, OS.linux, Architecture.x64, false),
      'iOS from a Mac': (ios, OS.macOS, Architecture.x64, true),
      'iOS from Windows': (ios, OS.windows, Architecture.x64, false),
      'Android from a Mac': (android, OS.macOS, Architecture.arm64, true),
      'Android from Linux': (android, OS.linux, Architecture.x64, true),
      'Android from Windows': (android, OS.windows, Architecture.x64, true),
      'Linux x64 from Linux x64': (linuxX64, OS.linux, Architecture.x64, true),
      'Linux arm64 from Linux x64': (
        linuxArm,
        OS.linux,
        Architecture.x64,
        false,
      ),
      'Linux x64 from a Mac': (linuxX64, OS.macOS, Architecture.arm64, false),
      'Windows from Windows': (windows, OS.windows, Architecture.x64, true),
      'Windows from Linux': (windows, OS.linux, Architecture.x64, false),
      'no triple': (
        const LottieNativeTarget(OS.android, Architecture.arm),
        OS.macOS,
        Architecture.arm64,
        false,
      ),
    };
    table.forEach((name, row) {
      final (target, os, arch, expected) = row;
      test(name, () {
        expect(target.buildableOn(hostOs: os, hostArch: arch), expected);
      });
    });

    test('Linux cross-compiles when the app sets that triple\'s linker', () {
      expect(
        linuxArm.buildableOn(
          hostOs: OS.linux,
          hostArch: Architecture.x64,
          environment: {'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER': 'gcc'},
        ),
        isTrue,
      );
    });
  });

  group('LottieNativeTarget.toString', () {
    test('names os, architecture and sdk for a log line', () {
      expect(
        const LottieNativeTarget(
          OS.iOS,
          Architecture.x64,
          sdk: IOSSdk.iPhoneSimulator,
        ).toString(),
        allOf(contains('ios'), contains('x64'), contains('iphonesimulator')),
      );
    });
  });
}
