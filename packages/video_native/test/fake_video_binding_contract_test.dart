import 'dart:convert';
import 'dart:typed_data';

import 'package:video_native/testing.dart';
import 'package:video_native/video_native.dart';

void main() {
  final valid = Uint8List.fromList(utf8.encode('a video'));
  const info = VideoInfo(
    width: 320,
    height: 240,
    duration: Duration(milliseconds: 500),
    frameRate: 10,
    hasAlpha: true,
  );

  VideoBindingContract.run(() {
    final fake = FakeVideoBinding()..accept(valid, info, frameCount: 5);
    return VideoBindingHarness(
      binding: fake,
      validBytes: valid,
      expectedInfo: info,
      frameCount: 5,
      malformedBytes: Uint8List.fromList(utf8.encode('not a video')),
      unavailable: () =>
          FakeVideoBinding(availability: VideoAvailability.missingLibrary),
    );
  });
}
