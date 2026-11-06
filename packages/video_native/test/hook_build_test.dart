import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/ffmpeg_prefix.dart';
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
  });
}
