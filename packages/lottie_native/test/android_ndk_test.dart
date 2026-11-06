import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/android_ndk.dart';

/// A file system as a map of directory to the names inside it.
NdkFiles _fs(Map<String, List<String>> tree) =>
    NdkFiles(isDirectory: tree.containsKey, list: (dir) => tree[dir] ?? []);

/// The directories of one NDK that has clang wrappers for [apis].
Map<String, List<String>> _ndk(
  String root, {
  String tag = 'darwin-x86_64',
  List<int> apis = const [21, 24, 35],
}) => {
  root: ['toolchains'],
  '$root/toolchains/llvm/prebuilt/$tag/bin': [
    'llvm-ar',
    for (final api in apis) ...[
      'aarch64-linux-android$api-clang',
      'x86_64-linux-android$api-clang',
    ],
  ],
};

void main() {
  group('findAndroidNdk', () {
    const home = '/Users/u';
    const sdk = '$home/Library/Android/sdk';

    AndroidNdk find(
      Map<String, List<String>> tree, {
      Map<String, String> env = const {'HOME': home},
      OS os = OS.macOS,
    }) => findAndroidNdk(environment: env, hostOs: os, files: _fs(tree));

    test('fails with how to install it when there is none', () {
      expect(
        () => find({}),
        throwsA(
          isA<AndroidNdkUnavailable>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('NDK'), contains('ANDROID_NDK_HOME'), contains(sdk)),
          ),
        ),
      );
    });

    test('takes the highest version under the SDK folder', () {
      final ndk = find({
        '$sdk/ndk': ['28.1.1', '28.2.1'],
        ..._ndk('$sdk/ndk/28.1.1'),
        ..._ndk('$sdk/ndk/28.2.1'),
      });

      expect(ndk.root, '$sdk/ndk/28.2.1');
    });

    test('compares versions as numbers, not as text', () {
      final ndk = find({
        '$sdk/ndk': ['9.0.1', '28.0.1', '100.0.0'],
        ..._ndk('$sdk/ndk/9.0.1'),
        ..._ndk('$sdk/ndk/28.0.1'),
        ..._ndk('$sdk/ndk/100.0.0'),
      });

      expect(ndk.root, '$sdk/ndk/100.0.0');
    });

    test('skips a version folder without a toolchain', () {
      final ndk = find({
        '$sdk/ndk': ['28.1.1', '28.2.1'],
        ..._ndk('$sdk/ndk/28.1.1'),
        '$sdk/ndk/28.2.1': ['source.properties'],
      });

      expect(ndk.root, '$sdk/ndk/28.1.1');
    });

    test('ignores folders that are not versions', () {
      final ndk = find({
        '$sdk/ndk': ['latest', '27.0.1'],
        ..._ndk('$sdk/ndk/27.0.1'),
      });

      expect(ndk.root, '$sdk/ndk/27.0.1');
    });

    test('ANDROID_NDK_HOME wins over everything', () {
      final ndk = find(
        {
          '$sdk/ndk': ['28.2.1'],
          ..._ndk('$sdk/ndk/28.2.1'),
          ..._ndk('/opt/ndk-a'),
          ..._ndk('/opt/ndk-b'),
        },
        env: {
          'HOME': home,
          'ANDROID_NDK_HOME': '/opt/ndk-a',
          'ANDROID_NDK_ROOT': '/opt/ndk-b',
        },
      );

      expect(ndk.root, '/opt/ndk-a');
    });

    test('ANDROID_NDK_ROOT is next', () {
      final ndk = find(
        {..._ndk('/opt/ndk-b'), ..._ndk('$sdk/ndk/28.2.1')},
        env: {'HOME': home, 'ANDROID_NDK_ROOT': '/opt/ndk-b'},
      );

      expect(ndk.root, '/opt/ndk-b');
    });

    test('a variable that points at a bad layout is skipped and reported', () {
      final tree = {
        '/opt/broken': ['readme'],
        '$sdk/ndk': ['28.2.1'],
        ..._ndk('$sdk/ndk/28.2.1'),
      };

      expect(
        find(tree, env: {'HOME': home, 'ANDROID_NDK_HOME': '/opt/broken'}).root,
        '$sdk/ndk/28.2.1',
      );
      expect(
        () => find(
          {'/opt/broken': <String>[]},
          env: {'HOME': home, 'ANDROID_NDK_HOME': '/opt/broken'},
        ),
        throwsA(
          isA<AndroidNdkUnavailable>().having(
            (e) => e.toString(),
            'message',
            contains('/opt/broken'),
          ),
        ),
      );
    });

    test('ANDROID_HOME, then ANDROID_SDK_ROOT, name the SDK folder', () {
      final tree = {
        '/sdk-a/ndk': ['1.0.0'],
        ..._ndk('/sdk-a/ndk/1.0.0'),
        '/sdk-b/ndk': ['2.0.0'],
        ..._ndk('/sdk-b/ndk/2.0.0'),
      };

      expect(
        find(
          tree,
          env: {'ANDROID_HOME': '/sdk-a', 'ANDROID_SDK_ROOT': '/sdk-b'},
        ).root,
        '/sdk-a/ndk/1.0.0',
      );
      expect(
        find(tree, env: {'ANDROID_SDK_ROOT': '/sdk-b'}).root,
        endsWith('2.0.0'),
      );
    });

    test('the default SDK folder follows the host OS', () {
      expect(
        find(
          {
            '/home/u/Android/Sdk/ndk': ['1.0.0'],
            ..._ndk('/home/u/Android/Sdk/ndk/1.0.0', tag: 'linux-x86_64'),
          },
          env: {'HOME': '/home/u'},
          os: OS.linux,
        ).root,
        '/home/u/Android/Sdk/ndk/1.0.0',
      );
      expect(
        find(
          {
            'C:/Users/u/AppData/Local/Android/Sdk/ndk': ['1.0.0'],
            ..._ndk(
              'C:/Users/u/AppData/Local/Android/Sdk/ndk/1.0.0',
              tag: 'windows-x86_64',
            ),
          },
          env: {'LOCALAPPDATA': 'C:/Users/u/AppData/Local'},
          os: OS.windows,
        ).root,
        'C:/Users/u/AppData/Local/Android/Sdk/ndk/1.0.0',
      );
    });
  });

  group('AndroidNdk toolchain', () {
    AndroidNdk ndk({List<int> apis = const [21, 24, 35], OS os = OS.macOS}) {
      final tag = switch (os) {
        OS.linux => 'linux-x86_64',
        OS.windows => 'windows-x86_64',
        _ => 'darwin-x86_64',
      };
      return findAndroidNdk(
        environment: {'ANDROID_NDK_HOME': '/n'},
        hostOs: os,
        files: _fs(_ndk('/n', tag: tag, apis: apis)),
      );
    }

    const bin = '/n/toolchains/llvm/prebuilt/darwin-x86_64/bin';

    test('names the clang wrapper for the requested API level', () {
      expect(
        ndk().linker('aarch64-linux-android', 24),
        '$bin/aarch64-linux-android24-clang',
      );
      expect(
        ndk().linker('x86_64-linux-android', 35),
        '$bin/x86_64-linux-android35-clang',
      );
    });

    test('takes the lowest the NDK offers when the app asks for less', () {
      expect(
        ndk().linker('aarch64-linux-android', 16),
        '$bin/aarch64-linux-android21-clang',
      );
    });

    test('takes the highest it offers when the app asks for more', () {
      expect(
        ndk().linker('aarch64-linux-android', 99),
        '$bin/aarch64-linux-android35-clang',
      );
    });

    test('takes the nearest level below one it lacks', () {
      expect(
        ndk().linker('aarch64-linux-android', 30),
        '$bin/aarch64-linux-android24-clang',
      );
    });

    test('an NDK without wrappers for the triple is unusable', () {
      expect(
        () => ndk(apis: const []).linker('aarch64-linux-android', 24),
        throwsA(isA<AndroidNdkUnavailable>()),
      );
    });

    test('names llvm-ar', () {
      expect(ndk().ar, '$bin/llvm-ar');
    });

    test('on Windows the wrappers are .cmd and the archiver .exe', () {
      final windows = findAndroidNdk(
        environment: {'ANDROID_NDK_HOME': 'C:/n'},
        hostOs: OS.windows,
        files: _fs({
          'C:/n/toolchains/llvm/prebuilt/windows-x86_64/bin': [
            'llvm-ar.exe',
            'aarch64-linux-android24-clang.cmd',
          ],
        }),
      );

      expect(
        windows.linker('aarch64-linux-android', 24),
        'C:/n/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android24-clang.cmd',
      );
      expect(windows.ar, endsWith('/llvm-ar.exe'));
    });
  });
}
