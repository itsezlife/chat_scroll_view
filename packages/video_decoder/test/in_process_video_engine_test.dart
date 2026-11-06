import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/testing.dart';
import 'package:video_native/video_native.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);
const _info = VideoInfo(
  width: 64,
  height: 48,
  duration: Duration(milliseconds: 400),
  frameRate: 10,
  hasAlpha: false,
);

void main() {
  group('InProcessVideoEngine over the fake binding', () {
    VideoEngineContract.run(
      () => VideoEngineHarness(
        open: () async => InProcessVideoEngine(
          FakeVideoBinding()..accept(_bytes, _info, frameCount: 4),
        ),
        validBytes: _bytes,
        expectedInfo: _info,
        frameCount: 4,
        malformedBytes: Uint8List.fromList([9, 9]),
      ),
    );
  });
}
