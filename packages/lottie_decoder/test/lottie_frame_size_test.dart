import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';

LottieInfo _info(int width, int height) => LottieInfo(
  width: width,
  height: height,
  frameCount: 10,
  frameRate: 30,
  features: LottieFeatures.none,
);

void main() {
  group('LottieFrameSize.fitting', () {
    test('puts the longer side on the edge and keeps the aspect ratio', () {
      expect(
        LottieFrameSize.fitting(_info(200, 100), 100),
        const LottieFrameSize(100, 50),
      );
      expect(
        LottieFrameSize.fitting(_info(100, 200), 100),
        const LottieFrameSize(50, 100),
      );
      expect(
        LottieFrameSize.fitting(_info(512, 512), 64),
        const LottieFrameSize(64, 64),
      );
    });

    test('rounds, and never drops a side below one pixel', () {
      expect(
        LottieFrameSize.fitting(_info(300, 100), 100),
        const LottieFrameSize(100, 33),
      );
      expect(
        LottieFrameSize.fitting(_info(1000, 1), 10),
        const LottieFrameSize(10, 1),
      );
    });

    test('scales up as well as down', () {
      expect(
        LottieFrameSize.fitting(_info(32, 16), 64),
        const LottieFrameSize(64, 32),
      );
    });
  });

  test('toBindingJob carries every field, the address as a pointer', () {
    const job = LottieEngineJob(
      handle: LottieHandle(7),
      frame: 2.5,
      width: 16,
      height: 8,
      address: 0x1000,
      strideBytes: 64,
    );

    final bindingJob = job.toBindingJob();

    expect(bindingJob.handle, const LottieHandle(7));
    expect(bindingJob.frame, 2.5);
    expect(bindingJob.width, 16);
    expect(bindingJob.height, 8);
    expect(bindingJob.target.address, 0x1000);
    expect(bindingJob.strideBytes, 64);
  });
}
