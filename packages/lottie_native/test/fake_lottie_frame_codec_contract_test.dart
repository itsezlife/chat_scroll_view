import 'package:lottie_native/testing.dart';

void main() {
  LottieFrameCodecContract.run(
    () => LottieFrameCodecHarness(
      codec: FakeLottieFrameCodec(),
      unavailable: () => FakeLottieFrameCodec(isAvailable: false),
    ),
  );
}
