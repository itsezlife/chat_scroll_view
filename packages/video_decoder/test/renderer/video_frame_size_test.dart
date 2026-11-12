import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

VideoInfo _info(int width, int height) => VideoInfo(
  width: width,
  height: height,
  duration: const Duration(seconds: 1),
  frameRate: 30,
  hasAlpha: false,
);

void main() {
  group('VideoFrameSize.edgeFor', () {
    test('snaps a requested edge up to the next size class', () {
      expect(VideoFrameSize.edgeFor(100), 128);
      expect(VideoFrameSize.edgeFor(128), 128);
      expect(VideoFrameSize.edgeFor(129), 256);
      // A GIF in a chat bubble or a panel row at 3x decodes at 384, not 512.
      expect(VideoFrameSize.edgeFor(336), 384);
      expect(VideoFrameSize.edgeFor(385), 512);
    });

    test('caps at the largest class', () {
      expect(VideoFrameSize.edgeFor(2000), 512);
    });

    test('honours the classes it is given', () {
      expect(VideoFrameSize.edgeFor(70, classes: const [50, 100]), 100);
    });
  });

  group('VideoFrameSize.fitting', () {
    test('puts the longer side on the edge and keeps the aspect', () {
      expect(
        VideoFrameSize.fitting(_info(320, 240), 128),
        const VideoFrameSize(128, 96),
      );
      expect(
        VideoFrameSize.fitting(_info(240, 320), 128),
        const VideoFrameSize(96, 128),
      );
    });

    test('never goes below one pixel', () {
      expect(
        VideoFrameSize.fitting(_info(1000, 1), 64),
        const VideoFrameSize(64, 1),
      );
    });
  });
}
