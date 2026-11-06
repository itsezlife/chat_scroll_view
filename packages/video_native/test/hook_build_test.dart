import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/android_ndk.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/ffmpeg_prefix.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/video_target.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/wrapper_compile.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('video_native_hook'));
  tearDown(() => temp.deleteSync(recursive: true));

  Directory prefixWith(String name, {List<String> lib = const []}) {
    final prefix = Directory('${temp.path}/$name')..createSync();
    Directory('${prefix.path}/include').createSync();
    Directory('${prefix.path}/lib').createSync();
    for (final file in lib) {
      File('${prefix.path}/lib/$file').writeAsStringSync('');
    }
    return prefix;
  }

  group('findFfmpegPrefix', () {
    test('finds the recipe output under native/.build', () {
      final native = Directory('${temp.path}/native')..createSync();
      final built = Directory('${native.path}/.build/macos-arm64/prefix')
        ..createSync(recursive: true);
      Directory('${built.path}/include').createSync();
      Directory('${built.path}/lib').createSync();

      final found = findFfmpegPrefix(
        native: native,
        target: 'macos-arm64',
        environment: const {},
      );

      expect(found?.path, built.path);
    });

    test('prefers the directory CHAT_VIDEO_FFMPEG_DIR names', () {
      final named = prefixWith('elsewhere');

      final found = findFfmpegPrefix(
        native: Directory('${temp.path}/native'),
        target: 'macos-arm64',
        environment: {ffmpegDirVariable: named.path},
      );

      expect(found?.path, named.path);
    });

    test('is null when the prefix is absent or incomplete', () {
      final native = Directory('${temp.path}/native')..createSync();
      Directory(
        '${native.path}/.build/macos-arm64/prefix/include',
      ).createSync(recursive: true);

      expect(
        findFfmpegPrefix(
          native: native,
          target: 'macos-arm64',
          environment: const {},
        ),
        isNull,
        reason: 'no lib/',
      );
      expect(
        findFfmpegPrefix(
          native: native,
          target: 'linux-x64',
          environment: const {},
        ),
        isNull,
        reason: 'no such target',
      );
    });
  });

  group('bundledLibraries', () {
    test('maps each library to the name its dependents load it under', () {
      final prefix = prefixWith(
        'p',
        lib: [
          for (final lib in [
            'avutil.61',
            'avcodec.63',
            'avformat.63',
            'swscale.10',
          ]) ...[
            'lib$lib.1.102.dylib'.replaceFirst('.1.102', ''),
            'lib$lib.dylib',
          ],
        ],
      );

      final libraries = bundledLibraries(prefix);

      expect(
        libraries.keys,
        unorderedEquals([
          'libavutil.61.dylib',
          'libavcodec.63.dylib',
          'libavformat.63.dylib',
          'libswscale.10.dylib',
        ]),
      );
    });

    test('names what a half-built prefix lacks', () {
      final prefix = prefixWith('p', lib: ['libavutil.61.dylib']);

      expect(
        () => bundledLibraries(prefix),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('libavcodec'), contains('libswscale')),
          ),
        ),
      );
    });
  });

  group('wrapperCompileArguments', () {
    test('link the four libraries, hide symbols and leave header room', () {
      final arguments = wrapperCompileArguments(
        source: 'a.c',
        includeDir: 'inc',
        prefix: '/p',
        output: 'out.dylib',
      );

      expect(
        arguments,
        containsAll([
          '-lavformat',
          '-lavcodec',
          '-lavutil',
          '-lswscale',
          '-fvisibility=hidden',
          '-Wl,-headerpad_max_install_names',
          '-Wl,-install_name,@rpath/libchat_video.dylib',
          '-I/p/include',
          '-L/p/lib',
        ]),
      );
    });

    // Xcode runs the hook with only PATH, HOME and TMPDIR, and puts its own
    // toolchain first in PATH: that `cc` has no SDK to default to, so the
    // wrapper's first system include (errno.h) is not found unless the
    // sysroot is passed.
    test('name the SDK when given one, and leave it to the compiler '
        'otherwise', () {
      List<String> arguments({String? sysroot}) => wrapperCompileArguments(
        source: 'a.c',
        includeDir: 'inc',
        prefix: '/p',
        output: 'out.dylib',
        sysroot: sysroot,
      );

      final withSdk = arguments(sysroot: '/sdk/MacOSX.sdk');

      expect(withSdk.sublist(withSdk.indexOf('-isysroot')).take(2), [
        '-isysroot',
        '/sdk/MacOSX.sdk',
      ]);
      expect(arguments(), isNot(contains('-isysroot')));
    });
  });

  group('recipeTarget', () {
    test('builds macOS and Android on arm64 only', () {
      expect(recipeTarget(OS.macOS, Architecture.arm64), 'macos-arm64');
      expect(recipeTarget(OS.android, Architecture.arm64), 'android-arm64');
      for (final architecture in [
        Architecture.x64,
        Architecture.arm,
        Architecture.ia32,
      ]) {
        expect(recipeTarget(OS.android, architecture), isNull);
      }
      expect(recipeTarget(OS.macOS, Architecture.x64), isNull);
      expect(recipeTarget(OS.iOS, Architecture.arm64), isNull);
    });

    test('builds iOS arm64 for the device and for the simulator', () {
      expect(
        recipeTarget(OS.iOS, Architecture.arm64, iosSdk: IOSSdk.iPhoneOS),
        'ios-arm64',
      );
      expect(
        recipeTarget(
          OS.iOS,
          Architecture.arm64,
          iosSdk: IOSSdk.iPhoneSimulator,
        ),
        'ios-sim-arm64',
      );
    });

    test('has no x86_64 simulator build', () {
      expect(
        recipeTarget(OS.iOS, Architecture.x64, iosSdk: IOSSdk.iPhoneSimulator),
        isNull,
      );
    });
  });

  group('bundledLibraries on iOS', () {
    test('names them as on macOS: the versioned dylib is the install name', () {
      final prefix = prefixWith(
        'p',
        lib: [
          'libavutil.61.dylib',
          'libavcodec.63.dylib',
          'libavformat.63.dylib',
          'libswscale.10.dylib',
        ],
      );

      expect(
        bundledLibraries(prefix, os: OS.iOS).keys,
        unorderedEquals([
          'libavutil.61.dylib',
          'libavcodec.63.dylib',
          'libavformat.63.dylib',
          'libswscale.10.dylib',
        ]),
      );
    });
  });

  group('iosWrapperCompileArguments', () {
    List<String> arguments({
      required IOSSdk sdk,
      String sdkPath = '/sdk/iPhoneOS.sdk',
    }) => iosWrapperCompileArguments(
      source: 'a.c',
      includeDir: 'inc',
      prefix: '/p',
      output: 'out.dylib',
      sdk: sdk,
      sdkPath: sdkPath,
      minVersion: 15,
    );

    test('target the device and name its SDK', () {
      final device = arguments(sdk: IOSSdk.iPhoneOS);

      expect(device, containsAllInOrder(['-target', 'arm64-apple-ios15.0']));
      expect(device, containsAllInOrder(['-isysroot', '/sdk/iPhoneOS.sdk']));
    });

    test('target the simulator by its own triple', () {
      final simulator = arguments(
        sdk: IOSSdk.iPhoneSimulator,
        sdkPath: '/sdk/iPhoneSimulator.sdk',
      );

      expect(
        simulator,
        containsAllInOrder(['-target', 'arm64-apple-ios15.0-simulator']),
      );
      expect(simulator, isNot(contains('arm64-apple-ios15.0')));
    });

    test('link, hide symbols and leave room for the install-name rewrite', () {
      expect(
        arguments(sdk: IOSSdk.iPhoneOS),
        containsAll([
          '-lavformat',
          '-lavcodec',
          '-lavutil',
          '-lswscale',
          '-fvisibility=hidden',
          '-Wl,-headerpad_max_install_names',
          '-Wl,-install_name,@rpath/libchat_video.dylib',
          '-I/p/include',
          '-L/p/lib',
        ]),
      );
    });
  });

  group('recipeCommandFor', () {
    test('names the TARGET only where the default would be wrong', () {
      expect(recipeCommandFor('macos-arm64'), recipeCommand);
      expect(
        recipeCommandFor('android-arm64'),
        'TARGET=android-arm64 $recipeCommand',
      );
    });
  });

  group('bundledLibraries on Android', () {
    test('maps each library to its unversioned soname, ignoring libvpx.a', () {
      final prefix = prefixWith(
        'p',
        lib: [
          for (final lib in ['avutil', 'avcodec', 'avformat', 'swscale'])
            'lib$lib.so',
          'libvpx.a',
        ],
      );

      final libraries = bundledLibraries(prefix, os: OS.android);

      expect(
        libraries.keys,
        unorderedEquals([
          'libavutil.so',
          'libavcodec.so',
          'libavformat.so',
          'libswscale.so',
        ]),
      );
    });

    test('does not mistake the macOS names for Android ones', () {
      final prefix = prefixWith(
        'p',
        lib: [
          'libavutil.61.dylib',
          'libavcodec.63.dylib',
          'libavformat.63.dylib',
          'libswscale.10.dylib',
        ],
      );

      expect(
        () => bundledLibraries(prefix, os: OS.android),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('libavcodec.so'),
          ),
        ),
      );
    });
  });

  group('androidWrapperCompileArguments', () {
    final arguments = androidWrapperCompileArguments(
      source: 'a.c',
      includeDir: 'inc',
      prefix: '/p',
      libraries: ['/p/lib/libavcodec.so', '/p/lib/libavutil.so'],
      output: 'out.so',
    );

    test('link the libraries by file, so the files the prefix holds', () {
      expect(
        arguments,
        containsAllInOrder(['/p/lib/libavcodec.so', '/p/lib/libavutil.so']),
      );
      expect(arguments, isNot(contains('-lavcodec')));
    });

    test('name the soname, align for 16 KiB pages and hide symbols', () {
      expect(
        arguments,
        containsAll([
          '-shared',
          '-fPIC',
          '-fvisibility=hidden',
          '-Wl,-soname,libchat_video.so',
          '-Wl,-z,max-page-size=16384',
          '-I/p/include',
        ]),
      );
      expect(arguments.join(' '), isNot(contains('-isysroot')));
    });
  });

  group('AndroidNdk', () {
    NdkFiles fs(Map<String, List<String>> tree) =>
        NdkFiles(isDirectory: tree.containsKey, list: (d) => tree[d] ?? []);
    const sdk = '/Users/u/Library/Android/sdk';
    String bin(String version) =>
        '$sdk/ndk/$version/toolchains/llvm/prebuilt/darwin-x86_64/bin';

    test('takes the highest NDK and the API level nearest below the ask', () {
      final ndk = findAndroidNdk(
        environment: const {'HOME': '/Users/u'},
        hostOs: OS.macOS,
        files: fs({
          '$sdk/ndk': ['28.1.1', '28.2.1'],
          bin('28.1.1'): ['aarch64-linux-android21-clang'],
          bin('28.2.1'): [
            for (final api in [21, 24, 29]) 'aarch64-linux-android$api-clang',
          ],
        }),
      );

      expect(ndk.root, '$sdk/ndk/28.2.1');
      expect(
        ndk.linker('aarch64-linux-android', 26),
        '${bin('28.2.1')}/aarch64-linux-android24-clang',
      );
    });

    test('says what to install when there is no NDK', () {
      expect(
        () => findAndroidNdk(
          environment: const {'HOME': '/Users/u'},
          hostOs: OS.macOS,
          files: fs({}),
        ),
        throwsA(isA<AndroidNdkUnavailable>()),
      );
    });
  });
}
