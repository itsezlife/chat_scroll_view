import 'dart:convert';
import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';

/// A hand-authored 100x100, 30 fps, 60 frame animation: one rotating 60x60
/// square filled with 50% opaque orange. Not a corpus sticker.
const _fixture = '''
{"v":"5.5.2","fr":30,"ip":0,"op":60,"w":100,"h":100,"nm":"fixture","ddd":0,
"assets":[],
"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"square","sr":1,
"ks":{"o":{"a":0,"k":100},
"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.5],"y":[1]},"o":{"x":[0.5],"y":[0]}},{"t":60,"s":[90]}]},
"p":{"a":0,"k":[50,50,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
"ao":0,
"shapes":[{"ty":"gr","it":[
{"ty":"rc","d":1,"s":{"a":0,"k":[60,60]},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0}},
{"ty":"fl","c":{"a":0,"k":[1,0.5,0.25,1]},"o":{"a":0,"k":50},"r":1},
{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
]}],"ip":0,"op":60,"st":0,"bm":0}]}''';

/// Runs the frame renderer contract over a [PixelCopyFrameRenderer] of the
/// engine [open] makes, loading [bytes] as the renderable file and [badBytes]
/// as the one it rejects.
void _runContract(
  LottieEngine Function() open,
  Uint8List bytes,
  Uint8List badBytes, {
  required int frameStep,
}) {
  FrameRendererContract.run(() {
    final engine = open();
    addTearDown(engine.close);
    final memory = ListFramePageMemory();
    // The contract's jobs are built synchronously; the handles come from a
    // load that completes at once on an in-process engine.
    late LottieHandle good;
    late LottieHandle bad;
    engine.load(bytes).then((r) => good = (r as LottieLoaded).handle);
    engine.load(badBytes).then((r) {
      bad = r is LottieLoaded ? r.handle : const LottieHandle(-1);
    });
    FrameJob job(FrameSlot slot, int frame, LottieHandle source) => FrameJob(
      slot: slot,
      frame: frame * frameStep,
      width: 48,
      height: 48,
      source: LottieSource(source, frameCount: 60),
    );
    return FrameRendererHarness(
      renderer: PixelCopyFrameRenderer(engine),
      memory: memory,
      job: (slot, frame) => job(slot, frame, good),
      unrenderable: (slot) => job(slot, 0, bad),
    );
  });
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );

  group('over a pixel-only engine', () {
    _runContract(
      () => FakePixelLottieEngine()..accept(bytes, info),
      bytes,
      Uint8List.fromList([9]),
      frameStep: 1,
    );
  });

  final native = NativeLottieBinding.probe().isAvailable;
  group(
    'over the native library',
    () {
      _runContract(
        () => InProcessLottieEngine(NativeLottieBinding.probe()),
        Uint8List.fromList(utf8.encode(_fixture)),
        Uint8List.fromList(utf8.encode('not a lottie file')),
        frameStep: 20,
      );
    },
    skip: native
        ? false
        : 'The native library is absent or speaks another ABI version: the '
              'build hook compiles it with cargo on macOS only (rustup.rs).',
  );

  group('PixelCopyFrameRenderer', () {
    late FakePixelLottieEngine engine;
    late ListFramePageMemory memory;
    late PixelCopyFrameRenderer renderer;
    late LottieHandle handle;
    late FrameSlot slot;

    setUp(() async {
      engine = FakePixelLottieEngine()..accept(bytes, info);
      memory = ListFramePageMemory();
      renderer = PixelCopyFrameRenderer(engine);
      handle = ((await engine.load(bytes)) as LottieLoaded).handle;
      final allocator = FrameSlotAllocator(
        pageSideFor: (_) => 128,
        budgetBytes: 2 * 128 * 128 * 4,
        sizeClasses: const [64],
      );
      // The fifth cell of a 2 x 2 grid: top left of the second page.
      for (var i = 0; i < 3; i++) {
        allocator.allocate(48, 48);
      }
      slot = allocator.allocate(48, 48)!;
    });

    FrameJob job(Object source, {int frame = 2}) => FrameJob(
      slot: slot,
      frame: frame,
      width: 48,
      height: 48,
      source: source,
    );

    test('copies every row to the slot offset, a page stride apart', () async {
      final held = await renderer.render([
        job(LottieSource(handle, frameCount: 10)),
      ], memory);

      expect(held, [0]);
      final page = memory.page(slot.pageIndex, side: slot.pageSide);
      final left = slot.rect.left.toInt();
      final top = slot.rect.top.toInt();
      List<int> pixelAt(int x, int y) {
        final at = ((top + y) * 128 + left + x) * 4;
        return page.sublist(at, at + 4);
      }

      // Literals: the column, the row and the frame of the pixel, opaque.
      expect(pixelAt(0, 0), [0, 0, 2, 255]);
      expect(pixelAt(5, 0), [5, 0, 2, 255]);
      expect(pixelAt(0, 7), [0, 7, 2, 255]);
      expect(pixelAt(47, 47), [47, 47, 2, 255]);
      expect(page[((top * 128) + left + 48) * 4 + 3], 0, reason: 'past width');
      expect(page[((top * 128) + left - 1) * 4 + 3], 0, reason: 'left of it');
      expect(page[(((top + 48) * 128) + left) * 4 + 3], 0, reason: 'below it');
    });

    test('rejects a source that is not a LottieSource', () async {
      await expectLater(
        renderer.render([job(handle as Object)], memory),
        throwsArgumentError,
      );
    });

    test('renders a source that has a cache key: there is no cache', () async {
      final held = await renderer.render([
        job(
          LottieSource(
            handle,
            frameCount: 10,
            cacheKey: FrameCacheKey(
              contentHash: 'abc',
              width: 48,
              height: 48,
              engineVersion: 'v',
            ),
          ),
        ),
      ], memory);

      expect(held, [0]);
    });

    test('an engine error propagates', () async {
      await engine.close();

      await expectLater(
        renderer.render([job(LottieSource(handle, frameCount: 10))], memory),
        throwsStateError,
      );
    });
  });
}
