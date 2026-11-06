import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';

/// On the VM the barrel still carries the FFI half of the API next to the
/// value types: a type it lost would fail to compile here.
void main() {
  test('the barrel exports the native types on the VM', () {
    final reachable = <Type>[
      LottieBinding,
      LottieRenderJob,
      LottieFrameCodec,
      LottieFrameRegion,
      NativeLottieBinding,
      NativeLottieFrameCodec,
      LottieInfo,
      LottieLoadResult,
      LottieAvailability,
      LottieRenderStatus,
      LottieNativeVersion,
    ];

    expect(reachable.toSet(), hasLength(reachable.length));
  });
}
