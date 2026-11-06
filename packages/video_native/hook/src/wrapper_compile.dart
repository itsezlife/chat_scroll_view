/// Compiles `native/src/chat_video.c` into the wrapper library: a dylib with
/// the system C compiler on macOS, a `.so` with the NDK clang on Android.
library;

import 'dart:io';

/// The compiler arguments for macOS arm64: pure, so a test reads them
/// without compiling.
///
/// The FFmpeg libraries are linked by their install names (`@rpath/...`);
/// `@loader_path` lets the wrapper find them beside itself, which is how a
/// host test loads it. In a Flutter app the tool rewrites the install names
/// of every bundled asset instead.
///
/// [sysroot] is the macOS SDK. A build run by Xcode starts the hook with only
/// PATH, HOME and TMPDIR, and Xcode's toolchain first in PATH: that `cc` does
/// not default to an SDK, and without one the first system header the wrapper
/// includes (`errno.h`) is not found. Null leaves the compiler to its own
/// default, which is right from a shell.
List<String> wrapperCompileArguments({
  required String source,
  required String includeDir,
  required String prefix,
  required String output,
  String? sysroot,
}) => [
  '-dynamiclib',
  '-std=c11',
  '-O2',
  '-Wall',
  '-Wextra',
  '-Werror',
  '-fvisibility=hidden',
  '-arch',
  'arm64',
  '-mmacosx-version-min=11.0',
  if (sysroot != null) ...['-isysroot', sysroot],
  '-I$includeDir',
  '-I$prefix/include',
  source,
  '-L$prefix/lib',
  '-lavformat',
  '-lavcodec',
  '-lavutil',
  '-lswscale',
  '-Wl,-install_name,@rpath/libchat_video.dylib',
  '-Wl,-rpath,@loader_path',
  // The Flutter tool rewrites install names to longer ones with
  // install_name_tool, which fails without room in the load commands.
  '-Wl,-headerpad_max_install_names',
  '-o',
  output,
];

/// The compiler arguments for Android: pure, like the macOS ones.
///
/// [libraries] are the FFmpeg `.so` files by path, not `-l` names: the exact
/// files the hook then bundles are the ones linked, whatever else the search
/// path holds. Each records its own soname (`libavcodec.so`) as NEEDED, the
/// name the APK carries it under. The loader needs no rpath: all of an app's
/// libraries sit in one directory.
List<String> androidWrapperCompileArguments({
  required String source,
  required String includeDir,
  required String prefix,
  required List<String> libraries,
  required String output,
}) => [
  '-shared',
  '-fPIC',
  '-std=c11',
  '-O2',
  '-Wall',
  '-Wextra',
  '-Werror',
  '-fvisibility=hidden',
  '-I$includeDir',
  '-I$prefix/include',
  source,
  ...libraries,
  '-llog',
  '-Wl,-soname,libchat_video.so',
  // Android 15 devices may run 16 KiB pages; Google Play requires 64-bit
  // libraries to be aligned for them.
  '-Wl,-z,max-page-size=16384',
  '-Wl,--no-undefined',
  '-o',
  output,
];

/// A compiler run that failed.
final class WrapperCompileFailed implements Exception {
  /// Creates the failure of [command] with its [output].
  const WrapperCompileFailed(this.command, this.output);

  /// The command line that was run.
  final String command;

  /// What the compiler printed.
  final String output;

  @override
  String toString() =>
      'video_native: compiling the wrapper failed.\n'
      '$command\n$output';
}

/// The macOS SDK `xcrun` names, or null when it cannot be asked (the compiler
/// then uses its own default).
Future<String?> macosSdkPath() async {
  try {
    final result = await Process.run('xcrun', [
      '--sdk',
      'macosx',
      '--show-sdk-path',
    ]);
    final path = '${result.stdout}'.trim();
    return result.exitCode == 0 && path.isNotEmpty ? path : null;
    // Any failure to ask is the answer "unknown", not a build failure: the
    // compile that follows says what is actually missing.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
}

/// Compiles the wrapper to [output] and returns it, against [sysroot] (the
/// macOS SDK `xcrun` names unless given).
Future<File> compileWrapper({
  required Directory native,
  required Directory prefix,
  required File output,
  String compiler = 'cc',
  String? sysroot,
}) async => runCompiler(
  compiler,
  wrapperCompileArguments(
    source: '${native.path}/src/chat_video.c',
    includeDir: '${native.path}/include',
    prefix: prefix.path,
    output: output.path,
    sysroot: sysroot ?? await macosSdkPath(),
  ),
  output,
);

/// Compiles the wrapper for Android with the NDK clang at [compiler].
Future<File> compileAndroidWrapper({
  required Directory native,
  required Directory prefix,
  required List<File> libraries,
  required File output,
  required String compiler,
}) => runCompiler(
  compiler,
  androidWrapperCompileArguments(
    source: '${native.path}/src/chat_video.c',
    includeDir: '${native.path}/include',
    prefix: prefix.path,
    libraries: [for (final library in libraries) library.path],
    output: output.path,
  ),
  output,
);

/// Runs [compiler] with [arguments] and returns [output], which it writes.
Future<File> runCompiler(
  String compiler,
  List<String> arguments,
  File output,
) async {
  await output.parent.create(recursive: true);
  final result = await Process.run(compiler, arguments);
  if (result.exitCode != 0) {
    throw WrapperCompileFailed(
      '$compiler ${arguments.join(' ')}',
      '${result.stdout}${result.stderr}',
    );
  }
  return output;
}
