import 'dart:convert';
import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

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

/// Runs the frame renderer contract over [binding], loading [bytes] as the
/// renderable file and [badBytes] as the one it rejects.
void _runContract(
  LottieBinding Function() binding,
  Uint8List bytes,
  Uint8List badBytes, {
  required int frameStep,
}) {
  FrameRendererContract.run(() {
    final engine = InProcessLottieEngine(binding());
    addTearDown(engine.close);
    final memory = NativeFramePageMemory(pageSide: 128);
    addTearDown(memory.dispose);
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
      source: source as Object,
    );
    return FrameRendererHarness(
      renderer: LottieFrameRenderer(engine, memory),
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

  _runContract(
    () => FakeLottieBinding()..accept(bytes, info),
    bytes,
    Uint8List.fromList([9]),
    frameStep: 1,
  );

  group('LottieFrameRenderer', () {
    late InProcessLottieEngine engine;
    late NativeFramePageMemory memory;
    late LottieFrameRenderer renderer;
    late LottieHandle handle;
    late FrameSlot slot;

    setUp(() async {
      engine = InProcessLottieEngine(FakeLottieBinding()..accept(bytes, info));
      memory = NativeFramePageMemory(pageSide: 128);
      renderer = LottieFrameRenderer(engine, memory);
      handle = ((await engine.load(bytes)) as LottieLoaded).handle;
      final allocator = FrameSlotAllocator(
        pageSide: 128,
        maxPages: 2,
        sizeClasses: const [64],
      );
      // The fifth cell of a 2 x 2 grid: top left of the second page.
      for (var i = 0; i < 3; i++) {
        allocator.allocate(48, 48);
      }
      slot = allocator.allocate(48, 48)!;
    });
    tearDown(() async {
      memory.dispose();
      await engine.close();
    });

    FrameJob job(Object source) =>
        FrameJob(slot: slot, frame: 2, width: 48, height: 48, source: source);

    test('rejects memory other than the one it was built for', () async {
      final other = NativeFramePageMemory(pageSide: 128);
      addTearDown(other.dispose);

      await expectLater(
        renderer.render([job(handle as Object)], other),
        throwsStateError,
      );
    });

    test('rejects a source that is not a handle', () async {
      await expectLater(
        renderer.render([job('nope')], memory),
        throwsArgumentError,
      );
    });

    test('writes at the slot offset with a page-wide stride', () async {
      await renderer.render([job(handle as Object)], memory);

      final page = memory.page(slot.pageIndex);
      final left = slot.rect.left.toInt();
      final top = slot.rect.top.toInt();
      int alphaAt(int x, int y) => page[(y * 128 + x) * 4 + 3];
      expect(alphaAt(left, top), isNot(0), reason: 'top left of the slot');
      expect(alphaAt(left + 47, top + 47), isNot(0), reason: 'last pixel');
      expect(alphaAt(left + 48, top), 0, reason: 'past the job width');
      expect(alphaAt(left - 1, top), 0, reason: 'left of the slot');
    });

    test('an engine error propagates', () async {
      await engine.close();

      await expectLater(
        renderer.render([job(handle as Object)], memory),
        throwsStateError,
      );
    });
  });

  final probe = NativeLottieBinding.probe();
  if (!probe.isAvailable) {
    test(
      'the contract over the native library',
      () {},
      skip:
          'The native library is absent or speaks another ABI version: the '
          'build hook compiles it with cargo on macOS only (rustup.rs).',
    );
    return;
  }
  group('over the native library', () {
    _runContract(
      NativeLottieBinding.probe,
      Uint8List.fromList(utf8.encode(_fixture)),
      Uint8List.fromList(utf8.encode('not a lottie file')),
      frameStep: 20,
    );
  });
}
