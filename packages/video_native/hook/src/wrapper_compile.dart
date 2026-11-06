/// Compiles `native/src/chat_video.c` into the wrapper dylib with the system
/// C compiler.
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
}) async {
  final arguments = wrapperCompileArguments(
    source: '${native.path}/src/chat_video.c',
    includeDir: '${native.path}/include',
    prefix: prefix.path,
    output: output.path,
    sysroot: sysroot ?? await macosSdkPath(),
  );
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
