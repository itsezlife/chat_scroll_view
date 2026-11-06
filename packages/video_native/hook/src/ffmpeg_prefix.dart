/// Finds the FFmpeg + libvpx install prefix the wrapper is compiled against,
/// and the shared libraries in it that must travel with the wrapper.
///
/// Kept apart from the hook entry so the lookup is tested without running a
/// build.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// The environment variable that names a prefix (a directory holding
/// `include/` and `lib/`) in place of the recipe's output.
const ffmpegDirVariable = 'CHAT_VIDEO_FFMPEG_DIR';

/// The command that produces the prefix this hook looks for by default.
const recipeCommand = 'packages/video_native/native/recipe/build.sh';

/// The command that builds the prefix for the recipe's [target].
String recipeCommandFor(String target) =>
    target == 'macos-arm64' ? recipeCommand : 'TARGET=$target $recipeCommand';

/// The libraries the wrapper links, by their short names.
const ffmpegLibraries = ['avutil', 'avcodec', 'avformat', 'swscale'];

/// The prefix to build against: [variable]'s value when set, else the
/// recipe's `.build/<target>/prefix` under [native]. Null when that
/// directory has no `include/` or no `lib/`.
Directory? findFfmpegPrefix({
  required Directory native,
  required String target,
  required Map<String, String> environment,
}) {
  final named = environment[ffmpegDirVariable];
  final candidate = Directory(
    named != null && named.isNotEmpty
        ? named
        : '${native.path}/.build/$target/prefix',
  );
  final complete =
      Directory('${candidate.path}/include').existsSync() &&
      Directory('${candidate.path}/lib').existsSync();
  return complete ? candidate : null;
}

/// The shared libraries of [prefix] by the name their dependents load them
/// under, one per entry of [ffmpegLibraries]: `libavcodec.63.dylib` on macOS
/// (the file whose install name is `@rpath/<that name>`), `libavcodec.so`
/// on Android (unversioned, and its own soname).
///
/// Throws a [StateError] naming what is missing, so a half-built prefix is a
/// message and not a link error.
Map<String, File> bundledLibraries(Directory prefix, {OS os = OS.macOS}) {
  final lib = Directory('${prefix.path}/lib');
  final names = [
    for (final entity in lib.listSync())
      if (entity is! Directory) entity.uri.pathSegments.last,
  ];
  final found = <String, File>{};
  final missing = <String>[];
  for (final short in ffmpegLibraries) {
    final pattern = os == OS.android
        ? RegExp('^lib$short\\.so\$')
        : RegExp('^lib$short\\.\\d+\\.dylib\$');
    final match = names.where(pattern.hasMatch).toList()..sort();
    if (match.isEmpty) {
      missing.add(
        os == OS.android ? 'lib$short.so' : 'lib$short.<major>.dylib',
      );
    } else {
      found[match.first] = File('${lib.path}/${match.first}');
    }
  }
  if (missing.isNotEmpty) {
    throw StateError(
      'The FFmpeg prefix ${prefix.path} lacks ${missing.join(', ')}.',
    );
  }
  return found;
}
