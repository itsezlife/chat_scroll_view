/// The three fixtures `video_native` commits, read by path, and the skip rule
/// for tests that need the native library.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:video_native/video_native.dart';

/// A committed fixture and what its generator command (video_native README)
/// says it is.
final class Fixture {
  const Fixture(
    this.file, {
    required this.width,
    required this.height,
    required this.frames,
    required this.frameRate,
    required this.hasAlpha,
  });

  final String file;
  final int width;
  final int height;
  final int frames;
  final double frameRate;
  final bool hasAlpha;

  Uint8List get bytes =>
      File('../video_native/native/probe/fixtures/$file').readAsBytesSync();

  /// A target size of the same aspect, small enough to keep tests quick.
  (int, int) get target => (width ~/ 4, height ~/ 4);
}

const mp4 = Fixture(
  'h264_320x240_30fps_2s.mp4',
  width: 320,
  height: 240,
  frames: 60,
  frameRate: 30,
  hasAlpha: false,
);

const webm = Fixture(
  'vp9_alpha_512x512_30fps_1s.webm',
  width: 512,
  height: 512,
  frames: 30,
  frameRate: 30,
  hasAlpha: true,
);

const gif = Fixture(
  'gif_64x48_10fps_1s.gif',
  width: 64,
  height: 48,
  frames: 10,
  frameRate: 10,
  hasAlpha: false,
);

const fixtures = [mp4, webm, gif];

/// Why the native tests cannot run here, or null when they can.
String? nativeSkipReason() {
  final binding = NativeVideoBinding.probe();
  return binding.isAvailable
      ? null
      : 'the native library is not bundled (${binding.availability}); build '
            'it with packages/video_native/native/recipe/build.sh';
}
