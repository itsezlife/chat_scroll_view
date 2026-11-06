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

  group('without a frame codec', () {
    // An engine whose codec is absent or unusable still renders; it just has
    // nothing to hand a cache, and cannot restore.
    for (final (name, codec) in <(String, LottieFrameCodec?)>[
      ('none', null),
      ('an unavailable one', FakeLottieFrameCodec(isAvailable: false)),
    ]) {
      test('$name: renderCapturing renders and carries no bytes', () async {
        final engine = InProcessLottieEngine(binding, codec: codec);
        final handle = ((await engine.load(bytes)) as LottieLoaded).handle;
        final target = calloc<Uint8>(64 * 4 * 64);
        addTearDown(() => calloc.free(target));

        final captures = await engine.renderCapturing([
          LottieEngineJob(
            handle: handle,
            frame: 3,
            width: 64,
            height: 64,
            address: target.address,
            strideBytes: 64 * 4,
          ),
        ]);

        expect(captures.single.status, LottieRenderStatus.ok);
        expect(captures.single.compressed, isNull);
        expect(target[3], isNot(0), reason: 'the frame still rendered');
      });

      test('$name: restore fails every job', () async {
        final engine = InProcessLottieEngine(binding, codec: codec);
        final target = calloc<Uint8>(64 * 4 * 64);
        addTearDown(() => calloc.free(target));

        final statuses = await engine.restore([
          LottieRestoreJob(
            compressed: Uint8List.fromList([1, 2, 3]),
            width: 64,
            height: 64,
            address: target.address,
            strideBytes: 64 * 4,
          ),
        ]);

        expect(statuses, [LottieRenderStatus.failed]);
      });
    }
  });

  group('close', () {
    test('closes the binding and is idempotent', () async {
      await engine.load(bytes);

      await engine.close();
      await engine.close();

      expect(binding.liveHandles, 0);
    });

    test('later calls throw LottieEngineClosed', () async {
      await engine.close();

      final closed = throwsA(isA<LottieEngineClosed>());
      await expectLater(engine.load(bytes), closed);
      await expectLater(engine.renderBatch(const []), closed);
      await expectLater(engine.dispose(const LottieHandle(1)), closed);
    });
  });
}
