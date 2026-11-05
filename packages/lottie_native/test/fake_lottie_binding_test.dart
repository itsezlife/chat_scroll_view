import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

void main() {
  final valid = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 100,
    height: 100,
    frameCount: 10,
    frameRate: 24,
    features: LottieFeatures.none,
  );
  late FakeLottieBinding binding;
  late Pointer<Uint8> memory;

  setUp(() {
    binding = FakeLottieBinding()..accept(valid, info);
    memory = calloc<Uint8>(4 * 4 * 4);
  });
  tearDown(() => calloc.free(memory));

  LottieHandle load() => (binding.load(valid) as LottieLoaded).handle;

  LottieRenderJob job(LottieHandle handle, double frame) => LottieRenderJob(
    handle: handle,
    frame: frame,
    width: 4,
    height: 4,
    target: memory,
    strideBytes: 16,
  );

  test('bytes that were not scripted are malformed', () {
    final result = binding.load(Uint8List.fromList([7]));

    expect(result, isA<LottieRejected>());
    expect((result as LottieRejected).reason, LottieRejection.malformed);
  });

  test('a scripted rejection reports its reason', () {
    final big = Uint8List.fromList([5]);
    binding.reject(big, LottieRejection.tooLarge);

    expect(
      (binding.load(big) as LottieRejected).reason,
      LottieRejection.tooLarge,
    );
  });

  test('a render fills the slot with one premultiplied colour per frame', () {
    final handle = load();

    binding.renderBatch([job(handle, 3)]);
    final first = Uint8List.fromList(memory.asTypedList(64));
    binding.renderBatch([job(handle, 4)]);
    final second = Uint8List.fromList(memory.asTypedList(64));

    expect(first, isNot(second));
    for (var p = 0; p < 64; p += 4) {
      expect(first.sublist(p, p + 4), first.sublist(0, 4));
      expect(first[p], lessThanOrEqualTo(first[p + 3]));
      expect(first[p + 1], lessThanOrEqualTo(first[p + 3]));
      expect(first[p + 2], lessThanOrEqualTo(first[p + 3]));
    }
  });

  test('a stride under the row width is a bad size', () {
    final handle = load();
    final bad = LottieRenderJob(
      handle: handle,
      frame: 0,
      width: 4,
      height: 4,
      target: memory,
      strideBytes: 8,
    );

    expect(binding.renderBatch([bad]), [LottieRenderStatus.badSize]);
  });

  test('a null target is a bad argument', () {
    final handle = load();
    final bad = LottieRenderJob(
      handle: handle,
      frame: 0,
      width: 4,
      height: 4,
      target: nullptr,
      strideBytes: 16,
    );

    expect(binding.renderBatch([bad]), [LottieRenderStatus.badArgument]);
  });

  test('renderFails turns every valid job into failed', () {
    final handle = load();
    binding.renderFails = true;

    expect(binding.renderBatch([job(handle, 0)]), [LottieRenderStatus.failed]);
  });

  test('a binding that is not available throws on render', () {
    final off = FakeLottieBinding(available: false);

    expect(off.isAvailable, isFalse);
    expect(() => off.renderBatch(const []), throwsStateError);
  });

  test('live reports the handles not yet disposed', () {
    final handle = load();
    expect(binding.liveHandles, 1);

    binding.dispose(handle);
    binding.dispose(handle);

    expect(binding.liveHandles, 0);
  });
}
