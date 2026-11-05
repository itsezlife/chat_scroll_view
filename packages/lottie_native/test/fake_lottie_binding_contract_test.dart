import 'dart:typed_data';

import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

void main() {
  final valid = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 512,
    height: 512,
    frameCount: 60,
    frameRate: 30,
    features: LottieFeatures.effects,
  );

  NativeBindingContract.run(
    () => NativeBindingHarness(
      binding: FakeLottieBinding()..accept(valid, info),
      validBytes: valid,
      expectedInfo: info,
      malformedBytes: Uint8List.fromList([9, 9]),
      laterFrame: 30,
      unavailable: () =>
          FakeLottieBinding(availability: LottieAvailability.missingLibrary),
    ),
  );
}
