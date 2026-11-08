import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

import '../support/texture_table.dart';

void main() {
  final table = TextureTable.compile();
  if (table == null) {
    test('texture writes', () {}, skip: TextureTable.skipReason);
    return;
  }
  final bytes = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );
  final key = FrameCacheKey(
    contentHash: 'abc123',
    width: 4,
    height: 2,
    engineVersion: '1.0.0',
  );

  late CountingLottieEngine engine;
  late NativeFramePageMemory memory;
  late FrameCache cache;
  late LottieSource source;
  late TableTextureHost host;

  setUp(() async {
    engine = CountingLottieEngine(
      InProcessLottieEngine(
        FakeLottieBinding()..accept(bytes, info),
        codec: FakeLottieFrameCodec(),
      ),
    );
    memory = NativeFramePageMemory();
    cache = FrameCache(directoryPath: null);
    host = TableTextureHost(table);
    final handle = ((await engine.load(bytes)) as LottieLoaded).handle;
    source = LottieSource(handle, frameCount: 10, cacheKey: key);
  });
  tearDown(() async {
    await cache.dispose();
    memory.dispose();
    await engine.close();
  });

  LottieFrameRenderer renderer({FrameTextureHost? textureHost}) =>
      LottieFrameRenderer(
        engine: engine,
        memory: memory,
        cache: cache,
        textureHost: textureHost ?? host,
      );

  Future<TextureFrameJob> job(int frame, {Object? from}) async =>
      TextureFrameJob(
        texture: AssetTexture(
          id: (await host.create(4, 4))!,
          width: 4,
          height: 4,
        ),
        frame: frame,
        width: 4,
        height: 2,
        source: from ?? source,
      );

  group('LottieFrameRenderer.write', () {
    test('draws each frame into its texture and posts it', () async {
      final jobs = [await job(1), await job(2)];

      final outcomes = await renderer().write(jobs);

      expect(outcomes, [
        TextureFrameOutcome.posted,
        TextureFrameOutcome.posted,
      ]);
      for (final job in jobs) {
        expect(table.postsOf(job.texture.id), 1);
      }
      expect(table.pixelAt(jobs[0].texture.id, 0, 1), [16, 8, 0, 200]);
      expect(table.pixelAt(jobs[1].texture.id, 0, 1), [32, 16, 0, 200]);
    });

    test(
      'restores a cached frame into a texture instead of drawing it',
      () async {
        final r = renderer();
        final first = await job(3);
        await r.write([first]);
        expect(engine.texturesRendered, 1);

        final second = await job(3);
        final outcomes = await r.write([second]);

        expect(outcomes, [TextureFrameOutcome.posted]);
        expect(engine.texturesRendered, 1, reason: 'nothing drawn again');
        expect(engine.texturesRestored, 1);
        expect(
          table.pixelsOf(second.texture.id, 4),
          table.pixelsOf(first.texture.id, 4),
        );
      },
    );

    test('a damaged cached frame is drawn after all and its animation '
        'forgotten', () async {
      for (var i = 0; i < info.frameCount; i++) {
        cache.put(key, i, Uint8List.fromList([9, 9, 9]), frameCount: 10);
      }

      final again = await job(5);
      final outcomes = await renderer().write([again]);

      expect(outcomes, [TextureFrameOutcome.posted]);
      expect(engine.texturesRestored, 1, reason: 'the entry was tried');
      expect(engine.texturesRendered, 1, reason: 'and drawn after it');
      expect(table.pixelAt(again.texture.id, 0, 1), [80, 40, 0, 200]);
      expect(cache.has(key, 4), isFalse, reason: 'the garbage went');
    });

    test('a texture that cannot be locked is skipped', () async {
      final busy = await job(1);
      table.refuseLocks(busy.texture.id);

      expect(await renderer().write([busy]), [TextureFrameOutcome.notLocked]);
    });

    test('fails every job without a texture host', () async {
      final r = LottieFrameRenderer(engine: engine, memory: memory);

      expect(await r.write([await job(1)]), [TextureFrameOutcome.failed]);
    });

    test('refuses a host whose entry points a render isolate cannot call', () {
      expect(
        () => renderer(textureHost: FakeFrameTextureHost()),
        throwsArgumentError,
      );
    });
  });
}
