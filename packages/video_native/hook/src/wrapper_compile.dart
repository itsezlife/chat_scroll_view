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
List<String> wrapperCompileArguments({
  required String source,
  required String includeDir,
  required String prefix,
  required String output,
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

/// Compiles the wrapper to [output] and returns it.
Future<File> compileWrapper({
  required Directory native,
  required Directory prefix,
  required File output,
  String compiler = 'cc',
}) async {
  final arguments = wrapperCompileArguments(
    source: '${native.path}/src/chat_video.c',
    includeDir: '${native.path}/include',
    prefix: prefix.path,
    output: output.path,
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
