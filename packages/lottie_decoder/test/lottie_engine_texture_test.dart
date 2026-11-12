import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

import 'support/texture_table.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);
const _info = LottieInfo(
  width: 64,
  height: 64,
  frameCount: 10,
  frameRate: 30,
  features: LottieFeatures.none,
);

// Built where it is used: a binding is single-isolate state.
LottieBinding _binding() => FakeLottieBinding()..accept(_bytes, _info);

LottieFrameCodec _codec() => FakeLottieFrameCodec();

/// The pixel `FakeLottieBinding` draws for frame 1: red 16, green 8, alpha
/// 200, premultiplied RGBA.
const _frameOne = [16, 8, 0, 200];

void main() {
  final table = TextureTable.compile();
  if (table == null) {
    test('texture writes', () {}, skip: TextureTable.skipReason);
    return;
  }

  final engines = <String, Future<LottieSlotEngine> Function()>{
    'in process': () async =>
        InProcessLottieEngine(_binding(), codec: _codec()),
    'on the render isolate': () => IsolateLottieEngine.spawn(
      bindingFactory: _binding,
      codecFactory: _codec,
    ),
    // The handle sits on the second isolate, and a restore may go to any.
    'on a pool of render isolates': () async {
      final engine = await IsolateLottieEngine.spawn(
        workers: 2,
        bindingFactory: _binding,
        codecFactory: _codec,
      );
      await engine.load(_bytes);
      return engine;
    },
  };

  for (final MapEntry(key: name, value: spawn) in engines.entries) {
    group('writeTextures $name', () {
      late LottieSlotEngine engine;
      late LottieHandle handle;

      setUp(() async {
        engine = await spawn();
        handle = (await engine.load(_bytes) as LottieLoaded).handle;
      });
      tearDown(() => engine.close());

      LottieTextureJob render(
        int texture, {
        int width = 4,
        int height = 2,
        double frame = 1,
        bool capture = false,
      }) => LottieTextureJob(
        texture: AssetTexture(id: texture, width: 4, height: 4),
        width: width,
        height: height,
        work: LottieTextureRender(handle, frame: frame, capture: capture),
      );

      test(
        'locks, draws the frame centred with clear margins, posts',
        () async {
          final id = table.create(4, 4, padding: 2, fill: 0x77);

          final results = await engine.writeTextures(
            table.entryPoints,
            FrameTextureFormat.rgba8888,
            [render(id)],
          );

          expect(results.single.outcome, TextureFrameOutcome.posted);
          expect(table.postsOf(id), 1);
          expect(table.isLocked(id), isFalse);
          expect(table.pixelAt(id, 0, 0), [0, 0, 0, 0], reason: 'a margin');
          expect(table.pixelAt(id, 0, 1), _frameOne, reason: 'row 1 of 2..3');
          expect(table.pixelAt(id, 3, 2), _frameOne);
          expect(table.pixelAt(id, 3, 3), [0, 0, 0, 0]);
          expect(
            table.pixelsOf(id, 4).sublist(16, 24),
            List.filled(8, 0x77),
            reason: 'the padding past a row is not the writer\'s',
          );
        },
      );

      test('writes in the host\'s channel order', () async {
        final id = table.create(4, 4);

        await engine.writeTextures(
          table.entryPoints,
          FrameTextureFormat.bgra8888,
          [render(id, width: 4, height: 4)],
        );

        expect(table.pixelAt(id, 0, 0), [0, 8, 16, 200]);
      });

      test('skips a texture that cannot be locked and posts nothing', () async {
        final busy = table.create(4, 4);
        final free = table.create(4, 4);
        table.refuseLocks(busy);

        final results = await engine.writeTextures(
          table.entryPoints,
          FrameTextureFormat.rgba8888,
          [render(busy), render(free)],
        );

        expect(
          [for (final r in results) r.outcome],
          [TextureFrameOutcome.notLocked, TextureFrameOutcome.posted],
        );
        expect(table.postsOf(busy), 0);
        expect(table.postsOf(free), 1);
      });

      test('a frame the engine cannot draw fails, and its texture is still '
          'unlocked', () async {
        final id = table.create(4, 4);
        await engine.dispose(handle);

        final results = await engine.writeTextures(
          table.entryPoints,
          FrameTextureFormat.rgba8888,
          [render(id)],
        );

        expect(results.single.outcome, TextureFrameOutcome.failed);
        expect(table.isLocked(id), isFalse);
      });

      test(
        'captures what it drew and restores it into another texture',
        () async {
          final first = table.create(4, 4);
          final second = table.create(4, 4, fill: 0x55);

          final captured = await engine.writeTextures(
            table.entryPoints,
            FrameTextureFormat.bgra8888,
            [render(first, capture: true)],
          );
          final bytes = captured.single.compressed!;
          final restored = await engine
              .writeTextures(table.entryPoints, FrameTextureFormat.bgra8888, [
                LottieTextureJob(
                  texture: AssetTexture(id: second, width: 4, height: 4),
                  width: 4,
                  height: 2,
                  work: LottieTextureRestore(CachedFrame.bytes(bytes)),
                ),
              ]);

          expect(restored.single.outcome, TextureFrameOutcome.posted);
          expect(
            table.pixelsOf(second, 4),
            table.pixelsOf(first, 4),
            reason:
                'the cache holds the engine\'s order, the host gets its own',
          );
        },
      );

      test('a restore of damaged bytes fails', () async {
        final id = table.create(4, 4);

        final results = await engine.writeTextures(
          table.entryPoints,
          FrameTextureFormat.rgba8888,
          [
            LottieTextureJob(
              texture: AssetTexture(id: id, width: 4, height: 4),
              width: 4,
              height: 2,
              work: LottieTextureRestore(
                CachedFrame.bytes(Uint8List.fromList([1, 2, 3])),
              ),
            ),
          ],
        );

        expect(results.single.outcome, TextureFrameOutcome.failed);
        expect(table.isLocked(id), isFalse);
      });
    });
  }
}
