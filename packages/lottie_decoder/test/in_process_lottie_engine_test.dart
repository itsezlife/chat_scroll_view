import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );

  late FakeLottieBinding binding;
  late LottieEngine engine;

  setUp(() {
    binding = FakeLottieBinding()..accept(bytes, info);
    engine = InProcessLottieEngine(binding);
  });

  test('load answers what the binding answers', () async {
    final loaded = await engine.load(bytes);
    final rejected = await engine.load(Uint8List.fromList([9]));

    expect(loaded, isA<LottieLoaded>());
    expect((loaded as LottieLoaded).info, info);
    expect(rejected, isA<LottieRejected>());
  });

  test(
    'renderBatch writes through the address and answers in job order',
    () async {
      final handle = ((await engine.load(bytes)) as LottieLoaded).handle;
      final target = calloc<Uint8>(64 * 4 * 64);
      addTearDown(() => calloc.free(target));

      final statuses = await engine.renderBatch([
        LottieEngineJob(
          handle: handle,
          frame: 3,
          width: 64,
          height: 64,
          address: target.address,
          strideBytes: 64 * 4,
        ),
        LottieEngineJob(
          handle: const LottieHandle(999),
          frame: 0,
          width: 64,
          height: 64,
          address: target.address,
          strideBytes: 64 * 4,
        ),
      ]);

      expect(statuses, [LottieRenderStatus.ok, LottieRenderStatus.badArgument]);
      expect(target[3], isNot(0), reason: 'alpha was written');
    },
  );

  test('dispose releases the handle', () async {
    final handle = ((await engine.load(bytes)) as LottieLoaded).handle;

    await engine.dispose(handle);

    expect(binding.liveHandles, 0);
  });

  group('close', () {
    test('closes the binding and is idempotent', () async {
      await engine.load(bytes);

      await engine.close();
      await engine.close();

      expect(binding.liveHandles, 0);
    });

    test('later calls throw StateError', () async {
      await engine.close();

      await expectLater(engine.load(bytes), throwsStateError);
      await expectLater(engine.renderBatch(const []), throwsStateError);
      await expectLater(
        engine.dispose(const LottieHandle(1)),
        throwsStateError,
      );
    });
  });
}
