import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/android_ndk.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/build_environment.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/targets.dart';

const _bin = '/n/toolchains/llvm/prebuilt/darwin-x86_64/bin';
const _pageFlag = '-C\x1flink-arg=-Wl,-z,max-page-size=16384';

AndroidNdk _ndk() => findAndroidNdk(
  environment: {'ANDROID_NDK_HOME': '/n'},
  hostOs: OS.macOS,
  files: NdkFiles(
    isDirectory: (path) => path == _bin,
    list: (path) => [
      'llvm-ar',
      for (final api in [21, 24, 35]) ...[
        'aarch64-linux-android$api-clang',
        'x86_64-linux-android$api-clang',
      ],
    ],
  ),
);

Map<String, String> _android(
  Architecture arch, {
  int api = 24,
  Map<String, String> env = const {},
}) => cargoBuildEnvironment(
  target: LottieNativeTarget(OS.android, arch, androidApi: api),
  environment: env,
  ndk: _ndk(),
);

void main() {
  group('cargoBuildEnvironment for Android', () {
    test('names the NDK linker and archiver of the arm64 triple', () {
      final env = _android(Architecture.arm64);

      expect(
        env['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER'],
        '$_bin/aarch64-linux-android24-clang',
      );
      expect(env['CARGO_TARGET_AARCH64_LINUX_ANDROID_AR'], '$_bin/llvm-ar');
    });

    test('names them for the x86_64 triple at the requested API level', () {
      final env = _android(Architecture.x64, api: 35);

      expect(
        env['CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER'],
        '$_bin/x86_64-linux-android35-clang',
      );
      expect(env['CARGO_TARGET_X86_64_LINUX_ANDROID_AR'], '$_bin/llvm-ar');
    });

    test('always asks for 16 KB pages', () {
      expect(
        _android(Architecture.arm64)['CARGO_ENCODED_RUSTFLAGS'],
        _pageFlag,
      );
    });

    test('appends to the encoded flags the app has set, never replaces', () {
      final env = _android(
        Architecture.arm64,
        env: {'CARGO_ENCODED_RUSTFLAGS': '-C\x1fopt-level=s'},
      );

      expect(env['CARGO_ENCODED_RUSTFLAGS'], '-C\x1fopt-level=s\x1f$_pageFlag');
    });

    test('appends to plain RUSTFLAGS, which it would otherwise shadow', () {
      // CARGO_ENCODED_RUSTFLAGS wins over RUSTFLAGS in cargo, so the app's
      // RUSTFLAGS must move into it or they are silently dropped.
      final env = _android(
        Architecture.arm64,
        env: {'RUSTFLAGS': '-C target-cpu=generic  -Zfoo'},
      );

      expect(
        env['CARGO_ENCODED_RUSTFLAGS'],
        '-C\x1ftarget-cpu=generic\x1f-Zfoo\x1f$_pageFlag',
      );
    });

    test('the encoded flags beat RUSTFLAGS, as they do in cargo', () {
      final env = _android(
        Architecture.arm64,
        env: {'CARGO_ENCODED_RUSTFLAGS': '-Cx', 'RUSTFLAGS': '-Cy'},
      );

      expect(env['CARGO_ENCODED_RUSTFLAGS'], '-Cx\x1f$_pageFlag');
    });

    test('an Android build without an NDK is a programming error', () {
      expect(
        () => cargoBuildEnvironment(
          target: const LottieNativeTarget(OS.android, Architecture.arm64),
          environment: const {},
        ),
        throwsArgumentError,
      );
    });
  });

  group('cargoBuildEnvironment for Apple targets', () {
    test('iOS sets the deployment target from the hook configuration', () {
      final env = cargoBuildEnvironment(
        target: const LottieNativeTarget(
          OS.iOS,
          Architecture.arm64,
          sdk: IOSSdk.iPhoneOS,
          iosVersion: 13,
        ),
        environment: const {},
      );

      expect(env, {'IPHONEOS_DEPLOYMENT_TARGET': '13.0'});
    });

    test('iOS without a configured version leaves the default', () {
      final env = cargoBuildEnvironment(
        target: const LottieNativeTarget(
          OS.iOS,
          Architecture.x64,
          sdk: IOSSdk.iPhoneSimulator,
        ),
        environment: const {},
      );

      expect(env, isEmpty);
    });

    test('macOS needs nothing', () {
      expect(
        cargoBuildEnvironment(
          target: const LottieNativeTarget(OS.macOS, Architecture.arm64),
          environment: const {},
        ),
        isEmpty,
      );
    });
  });
}
