/// Delivers the native library as the code asset that
/// `lib/src/native/chat_video_symbols.dart` binds to, plus the FFmpeg shared
/// libraries it links.
///
/// macOS arm64 and Android arm64-v8a: the wrapper is compiled (the system C
/// compiler, or the NDK clang) against the FFmpeg + libvpx prefix built by
/// `native/recipe/build.sh` for that target (or the one `CHAT_VIDEO_FFMPEG_DIR`
/// names). With no prefix, or on another target, no asset is emitted with a
/// warning and the probe reports `missingLibrary`; prebuilt delivery is a
/// later ticket.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'src/android_ndk.dart';
import 'src/ffmpeg_prefix.dart';
import 'src/video_target.dart';
import 'src/wrapper_compile.dart';

/// Names the asset `package:video_native/src/native/chat_video_symbols.dart`,
/// the library URI of the file whose `@Native` functions resolve against it.
const _assetName = 'src/native/chat_video_symbols.dart';

/// The NDK clang that targets arm64 Android at the app's API level.
String ndkClang(CodeConfig code) => findAndroidNdk(
  environment: Platform.environment,
  hostOs: OS.current,
).linker('aarch64-linux-android', code.android.targetNdkApi);

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = recipeTarget(code.targetOS, code.targetArchitecture);
    if (target == null) {
      stderr.writeln(
        'warning: video_native has no native library for '
        '${code.targetOS} ${code.targetArchitecture}: only macOS arm64 and '
        'Android arm64-v8a are built so far. No asset is bundled.',
      );
      return;
    }
    final android = code.targetOS == OS.android;

    final native = Directory.fromUri(input.packageRoot.resolve('native/'));
    final prefix = findFfmpegPrefix(
      native: native,
      target: target,
      environment: Platform.environment,
    );
    if (prefix == null) {
      // Watch the file the recipe will create, so that building it re-runs
      // the hook (a hook with no dependencies is never re-run). The
      // environment variable is not trackable: `flutter clean` after
      // changing it.
      output.dependencies.add(
        native.uri.resolve(
          '.build/$target/prefix/include/libavcodec/avcodec.h',
        ),
      );
      stderr.writeln(
        'warning: video_native found no FFmpeg build for $target, so no '
        'native video library is bundled. Build it with '
        '${recipeCommandFor(target)}, or set $ffmpegDirVariable to a prefix '
        'holding include/ and lib/. (Prebuilt delivery is a later ticket.)',
      );
      return;
    }

    final libraries = bundledLibraries(prefix, os: code.targetOS);
    // Every input as a file: a directory would miss an edit to a file in it.
    output.dependencies
      ..add(native.uri.resolve('src/chat_video.c'))
      ..add(native.uri.resolve('include/chat_video.h'))
      ..addAll([for (final file in libraries.values) file.uri]);

    final out = input.outputDirectory;
    final File wrapper;
    if (android) {
      final String clang;
      try {
        clang = ndkClang(code);
      } on AndroidNdkUnavailable catch (e) {
        // Not a failed build: an app without the NDK cannot play video, which
        // the probe reports, and the message says what to install.
        stderr.writeln('warning: $e No asset is bundled.');
        return;
      }
      wrapper = await compileAndroidWrapper(
        native: native,
        prefix: prefix,
        libraries: libraries.values.toList(),
        output: File.fromUri(out.resolve('libchat_video.so')),
        compiler: clang,
      );
    } else {
      wrapper = await compileWrapper(
        native: native,
        prefix: prefix,
        output: File.fromUri(out.resolve('libchat_video.dylib')),
      );
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: wrapper.uri,
      ),
    );

    // The FFmpeg libraries are bundled under the names the wrapper's install
    // records (macOS) or sonames (Android) ask for. Nothing binds
    // to them from Dart.
    for (final MapEntry(key: name, value: file) in libraries.entries) {
      final copy = await file.copy(File.fromUri(out.resolve(name)).path);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'ffmpeg/$name',
          linkMode: DynamicLoadingBundled(),
          file: copy.uri,
        ),
      );
    }
  });
}
