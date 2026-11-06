import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/testing.dart';
import 'package:video_native/video_native.dart';

// ignore: always_use_package_imports
import 'support/fixtures.dart';

void main() {
  final probe = NativeVideoBinding.probe();

  group('NativeVideoBinding', skip: nativeSkipReason(probe), () {
    VideoBindingContract.run(
      () => VideoBindingHarness(
        binding: NativeVideoBinding.probe(),
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
        unavailable: () => NativeVideoBinding.probing(() => 2),
      ),
    );
  });
}
