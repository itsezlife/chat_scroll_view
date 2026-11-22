/// The software video decoder's native library is built by its package's hook
/// against an FFmpeg build. The hook runner gives a hook none of the shell's
/// variables, and a git checkout of the package has no FFmpeg build of its
/// own, so the workspace names one: without it every video sticker and GIF
/// has no decoder and keeps its placeholder, and only a build warning says so.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the workspace names the FFmpeg build the video decoder links', () {
    final pubspec = loadYaml(File('../pubspec.yaml').readAsStringSync());

    final defines = pubspec['hooks']?['user_defines']?['mpx_video_decoder'];
    final build = defines?['ffmpeg_build'];

    expect(build, isA<String>());
    expect(
      build,
      endsWith('mpx_video_decoder/native/.build'),
      reason: 'the recipe build directory: <dir>/<target>/prefix',
    );
  });
}
