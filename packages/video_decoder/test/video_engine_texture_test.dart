import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/testing.dart';
import 'package:video_native/video_native.dart';

import 'support/texture_table.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);
const _info = VideoInfo(
  width: 64,
  height: 32,
  duration: Duration(milliseconds: 300),
  frameRate: 10,
  hasAlpha: true,
);

// Built where it is used: a binding is single-isolate state.
VideoBinding _binding() =>
    FakeVideoBinding()..accept(_bytes, _info, frameCount: 3);

/// The BGRA pixel `FakeVideoBinding` draws for its second frame: blue 16,
/// green 8, red 0, alpha 200.
const _secondBgra = [16, 8, 0, 200];

/// A frame source over one decoded frame.
final class _OneFrame implements VideoFrameSource {
  _OneFrame(this.clip, this.pixels);

  @override
  final VideoClip clip;
  final Uint8List? pixels;

  @override
  Uint8List? pixelsOf(int frame) => pixels;
}

void main() {
  final table = TextureTable.compile();
  if (table == null) {
    test('texture writes', () {}, skip: TextureTable.skipReason);
    return;
  }

  final engines = <String, Future<VideoTextureEngine> Function()>{
    'in process': () async => InProcessVideoEngine(_binding()),
    'on a decode worker': () =>
        IsolateVideoEngine.spawn(workers: 2, bindingFactory: _binding),
  };

  for (final MapEntry(key: name, value: spawn) in engines.entries) {
    group('writeTextures $name', () {
      late VideoTextureEngine engine;
      late VideoClip clip;
      late Uint8List second;

      setUp(() async {
        engine = await spawn();
        clip =
            (await engine.open(_bytes, width: 4, height: 2) as VideoClipOpened)
                .clip;
        final buffer = Uint8List(clip.frameBytes);
        await engine.nextFrame(clip, destination: buffer);
        await engine.nextFrame(clip, destination: buffer);
        second = buffer;
      });
      tearDown(() => engine.dispose());

      VideoTextureJob job(int texture) => VideoTextureJob(
        clip: clip,
        texture: AssetTexture(id: texture, width: 4, height: 4),
        pixels: second,
      );

      test(
        'copies the frame centred, swapped for an RGBA host, and posts',
        () async {
          final id = table.create(4, 4, padding: 1, fill: 0x77);

          final outcomes = await engine.writeTextures(
            table.entryPoints,
            FrameTextureFormat.rgba8888,
            [job(id)],
          );

          expect(outcomes, [TextureFrameOutcome.posted]);
          expect(table.postsOf(id), 1);
          expect(table.pixelAt(id, 0, 0), [0, 0, 0, 0], reason: 'a margin');
          expect(table.pixelAt(id, 2, 1), [0, 8, 16, 200]);
          expect(table.pixelAt(id, 4, 1), [0x77, 0x77, 0x77, 0x77]);
        },
      );

      test('keeps the decoder\'s order for a BGRA host', () async {
        final id = table.create(4, 4);

        await engine.writeTextures(
          table.entryPoints,
          FrameTextureFormat.bgra8888,
          [job(id)],
        );

        expect(table.pixelAt(id, 0, 2), _secondBgra);
      });

      test('skips a texture that cannot be locked', () async {
        final busy = table.create(4, 4);
        final free = table.create(4, 4);
        table.refuseLocks(busy);

        final outcomes = await engine.writeTextures(
          table.entryPoints,
          FrameTextureFormat.bgra8888,
          [job(busy), job(free)],
        );

        expect(outcomes, [
          TextureFrameOutcome.notLocked,
          TextureFrameOutcome.posted,
        ]);
        expect(table.postsOf(busy), 0);
      });

      test('the writer hands a source\'s frame over and fails a frame that is '
          'gone', () async {
        final host = TableTextureHost(table);
        final writer = VideoFrameTextureWriter(engine: engine, host: host);
        final id = table.create(4, 4);

        final outcomes = await writer.write([
          TextureFrameJob(
            texture: AssetTexture(id: id, width: 4, height: 4),
            frame: 1,
            width: 4,
            height: 2,
            source: _OneFrame(clip, second),
          ),
          TextureFrameJob(
            texture: AssetTexture(id: id, width: 4, height: 4),
            frame: 2,
            width: 4,
            height: 2,
            source: _OneFrame(clip, null),
          ),
        ]);

        expect(outcomes, [
          TextureFrameOutcome.posted,
          TextureFrameOutcome.failed,
        ]);
        expect(table.pixelAt(id, 1, 1), [0, 8, 16, 200]);
      });
    });
  }

  test('a writer refuses a host a decode worker cannot reach', () {
    expect(
      () => VideoFrameTextureWriter(
        engine: InProcessVideoEngine(_binding()),
        host: FakeFrameTextureHost(),
      ),
      throwsArgumentError,
    );
  });
}
