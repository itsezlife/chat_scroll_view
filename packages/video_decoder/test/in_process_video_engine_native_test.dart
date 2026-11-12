import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

import 'support/fixture_cases.dart';
import 'support/fixtures.dart';

Future<VideoEngine> _open() async =>
    InProcessVideoEngine(NativeVideoBinding.probe());

void main() {
  group(
    'InProcessVideoEngine over the native binding',
    skip: nativeSkipReason(),
    () {
      VideoEngineContract.run(
        () => VideoEngineHarness(
          open: _open,
          validBytes: mp4.bytes,
          expectedInfo: const VideoInfo(
            width: 320,
            height: 240,
            duration: Duration(milliseconds: 2000),
            frameRate: 30,
            hasAlpha: false,
          ),
          frameCount: mp4.frames,
          malformedBytes: Uint8List(2048),
        ),
      );
      group('fixtures', () => fixtureCases(_open));
    },
  );
}
