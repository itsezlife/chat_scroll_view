/// Checks a built native library against the target it is for; run by the
/// prebuilts workflow after every build and by `assemble_manifest.dart` for
/// every file it lists. From the package root:
///
/// ```sh
/// dart native/tool/verify_artifact.dart <file> <key>
/// ```
///
/// `<key>` is a manifest target key (`android-arm64`, `windows-x64`, ...).
/// Prints `OK` and exits 0, or prints the problem and exits 1 (64 for a usage
/// error). The judge is the hook's own header check, so CI and a consumer's
/// build agree on what a sound library is.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../hook/src/artifact_check.dart';
import '../../hook/src/targets.dart';

void main(List<String> args) {
  exitCode = runVerifyArtifact(args, out: stdout);
}

/// The command line of `native/tool/verify_artifact.dart`; returns the exit
/// code.
int runVerifyArtifact(List<String> args, {required StringSink out}) {
  if (args.length != 2) {
    out.writeln(
      'usage: dart native/tool/verify_artifact.dart <file> <key>\n'
      '  keys: ${LottieNativeTarget.keys.join(', ')}',
    );
    return 64;
  }
  final target = LottieNativeTarget.fromKey(args[1]);
  if (target == null) {
    out.writeln(
      'unknown key "${args[1]}"; keys: ${LottieNativeTarget.keys.join(', ')}',
    );
    return 64;
  }
  final problem = libraryProblem(File(args[0]), target);
  out.writeln(problem ?? 'OK');
  return problem == null ? 0 : 1;
}

/// Why [file] cannot be the library of [target], or null when it can.
///
/// An unreadable or empty file is a problem, not an exception.
String? libraryProblem(File file, LottieNativeTarget target) {
  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException catch (e) {
    return 'cannot read ${file.path}: ${e.message}';
  }
  if (bytes.isEmpty) return '${file.uri.pathSegments.last} is empty';
  return artifactProblem(bytes, target);
}
