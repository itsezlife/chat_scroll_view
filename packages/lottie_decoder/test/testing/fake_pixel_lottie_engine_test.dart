import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );

  LottieEngineContract.run(
    () => LottieEngineHarness<LottieEngine>(
      open: () async => FakePixelLottieEngine()..accept(bytes, info),
      validBytes: bytes,
      expectedInfo: info,
      malformedBytes: Uint8List.fromList([9]),
    ),
  );

  test('a pixel carries its column, row and frame, and is opaque', () async {
    final engine = FakePixelLottieEngine()..accept(bytes, info);
    final handle = ((await engine.load(bytes)) as LottieLoaded).handle;

    final pixels = (await engine.renderPixels([
      LottiePixelJob(handle: handle, frame: 2, width: 4, height: 3),
    ])).single!;

    // Row 1, column 3 of a 4 x 3 frame: bytes 28..31.
    expect(pixels.sublist(28, 32), [3, 1, 2, 255]);
  });
}
