import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

/// A binding that draws like the fake and then scribbles one byte past the
/// right edge of every slot: the defect the contract exists to catch.
final class _OverreachingBinding implements LottieBinding {
  _OverreachingBinding(this._inner);
  final LottieBinding _inner;

  @override
  bool get isAvailable => _inner.isAvailable;

  @override
  LottieAvailability get availability => _inner.availability;

  @override
  void close() => _inner.close();

  @override
  LottieLoadResult load(Uint8List bytes) => _inner.load(bytes);

  @override
  void dispose(LottieHandle handle) => _inner.dispose(handle);

  @override
  List<LottieRenderStatus> renderBatch(List<LottieRenderJob> jobs) {
    final statuses = _inner.renderBatch(jobs);
    for (var i = 0; i < jobs.length; i++) {
      if (statuses[i] == LottieRenderStatus.ok) {
        jobs[i].target[jobs[i].width * 4] = 0xFF;
      }
    }
    return statuses;
  }
}

void main() {
  final valid = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );

  NativeBindingHarness harness(LottieBinding Function(LottieBinding) wrap) =>
      NativeBindingHarness(
        binding: wrap(FakeLottieBinding()..accept(valid, info)),
        validBytes: valid,
        expectedInfo: info,
        malformedBytes: Uint8List.fromList([9]),
      );

  test('a renderer that writes outside its slot fails the contract', () {
    final mutant = harness(_OverreachingBinding.new);

    expect(
      () => NativeBindingContract.checkWritesInsideSlot(mutant),
      throwsA(isA<TestFailure>()),
    );
  });

  test('the same check passes for a renderer that stays inside', () {
    NativeBindingContract.checkWritesInsideSlot(harness((b) => b));
  });
}
