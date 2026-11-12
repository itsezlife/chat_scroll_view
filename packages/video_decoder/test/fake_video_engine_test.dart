import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
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
  group('FakeVideoEngine', () {
    VideoEngineContract.run(
      () => VideoEngineHarness(
        open: () async =>
            FakeVideoEngine()..accept(_bytes, _info, frameCount: 4),
        validBytes: _bytes,
        expectedInfo: _info,
        frameCount: 4,
        malformedBytes: Uint8List.fromList([9, 9]),
      ),
    );

    test('reports the clips still open', () async {
      final engine = FakeVideoEngine()..accept(_bytes, _info, frameCount: 4);
      final opened = await engine.open(_bytes, width: 8, height: 6);

      expect(engine.openClips, 1);
      await engine.close((opened as VideoClipOpened).clip);
      expect(engine.openClips, 0);
    });

    test('a scripted rejection is carried through', () async {
      final engine = FakeVideoEngine()
        ..reject(_bytes, VideoRejection.limitExceeded);

      final result = await engine.open(_bytes, width: 8, height: 6);

      expect(result, isA<VideoClipRejected>());
      expect(
        (result as VideoClipRejected).reason,
        VideoRejection.limitExceeded,
      );
    });
  });
}
