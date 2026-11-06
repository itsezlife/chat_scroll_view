import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

/// A codec that writes a byte into the target and only then validates: the
/// defect "a failed decompress leaves the target unchanged" exists to catch.
final class _WriteBeforeValidating implements LottieFrameCodec {
  _WriteBeforeValidating(this._inner);
  final LottieFrameCodec _inner;

  @override
  bool get isAvailable => _inner.isAvailable;

  @override
  Uint8List? compress(LottieFrameRegion region) => _inner.compress(region);

  @override
  bool decompress(Uint8List data, LottieFrameRegion region) {
    region.target[0] ^= 0xFF;
    return _inner.decompress(data, region);
  }
}

void main() {
  test('a decompress that writes before validating fails the contract', () {
    final mutant = LottieFrameCodecHarness(
      codec: _WriteBeforeValidating(FakeLottieFrameCodec()),
    );

    expect(
      () => LottieFrameCodecContract.checkCorruptDataLeavesTargetUnchanged(
        mutant,
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  test('the same check passes for a codec that validates first', () {
    LottieFrameCodecContract.checkCorruptDataLeavesTargetUnchanged(
      LottieFrameCodecHarness(codec: FakeLottieFrameCodec()),
    );
  });
}
