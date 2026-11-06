import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
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
    final memory = NativeFramePageMemory();
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
      source: LottieSource(source, frameCount: 60),
    );
    return FrameRendererHarness(
      renderer: LottieFrameRenderer(engine: engine, memory: memory),
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
      memory = NativeFramePageMemory();
      renderer = LottieFrameRenderer(engine: engine, memory: memory);
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
    tearDown(() async {
      memory.dispose();
      await engine.close();
    });

    FrameJob job(Object source) =>
        FrameJob(slot: slot, frame: 2, width: 48, height: 48, source: source);

    test('rejects memory other than the one it was built for', () async {
      final other = NativeFramePageMemory();
      addTearDown(other.dispose);

      await expectLater(
        renderer.render([job(LottieSource(handle, frameCount: 10))], other),
        throwsStateError,
      );
    });

    test('rejects a source that is not a LottieSource', () async {
      await expectLater(
        renderer.render([job(handle as Object)], memory),
        throwsArgumentError,
      );
    });

    test('writes at the slot offset with a page-wide stride', () async {
      await renderer.render([
        job(LottieSource(handle, frameCount: 10)),
      ], memory);

      final page = memory.page(slot.pageIndex, side: slot.pageSide);
      final left = slot.rect.left.toInt();
      final top = slot.rect.top.toInt();
      int alphaAt(int x, int y) => page[(y * 128 + x) * 4 + 3];
      expect(alphaAt(left, top), isNot(0), reason: 'top left of the slot');
      expect(alphaAt(left + 47, top + 47), isNot(0), reason: 'last pixel');
      expect(alphaAt(left + 48, top), 0, reason: 'past the job width');
      expect(alphaAt(left - 1, top), 0, reason: 'left of the slot');
    });

    test(
      'writes by the side of the slot, on pages of different sides',
      () async {
        // Class 64 opens a 128 px page, class 128 a 256 px one: the second
        // cell of the large page starts at x 128 and its rows are 256 px apart.
        final sized = FrameSlotAllocator(
          pageSideFor: (c) => 2 * c,
          budgetBytes: 1 << 20,
          sizeClasses: const [64, 128],
        );
        final small = sized.allocate(48, 48)!;
        sized.allocate(100, 100);
        final large = sized.allocate(100, 100)!;
        expect(large.pageSide, 256);
        expect(large.rect.left, 128);

        await renderer.render([
          FrameJob(
            slot: small,
            frame: 2,
            width: 48,
            height: 48,
            source: LottieSource(handle, frameCount: 10),
          ),
          FrameJob(
            slot: large,
            frame: 2,
            width: 100,
            height: 100,
            source: LottieSource(handle, frameCount: 10),
          ),
        ], memory);

        int alphaAt(FrameSlot slot, int x, int y) => memory.page(
          slot.pageIndex,
          side: slot.pageSide,
        )[(y * slot.pageSide + x) * 4 + 3];
        final left = large.rect.left.toInt();
        final top = large.rect.top.toInt();
        expect(alphaAt(large, left + 99, top + 99), isNot(0), reason: 'last');
        expect(alphaAt(large, left + 100, top), 0, reason: 'past the width');
        expect(alphaAt(large, left - 1, top), 0, reason: 'left of the cell');
        expect(alphaAt(small, 47, 47), isNot(0));
        expect(alphaAt(small, 48, 0), 0);
      },
    );

    test('an engine error propagates', () async {
      await engine.close();

      await expectLater(
        renderer.render([job(LottieSource(handle, frameCount: 10))], memory),
        throwsStateError,
      );
    });
  });

  group('with a frame cache', () {
    const side = 48;
    late CountingLottieEngine engine;
    late NativeFramePageMemory memory;
    late FrameSlotAllocator allocator;
    late LottieHandle handle;
    late FrameCacheKey key;

    LottieEngine open({required LottieFrameCodec? codec}) =>
        InProcessLottieEngine(
          FakeLottieBinding()..accept(bytes, info),
          codec: codec,
        );

    setUp(() async {
      engine = CountingLottieEngine(open(codec: FakeLottieFrameCodec()));
      memory = NativeFramePageMemory();
      allocator = FrameSlotAllocator(
        pageSideFor: (_) => 256,
        budgetBytes: 256 * 256 * 4,
        sizeClasses: const [64],
      );
      handle = ((await engine.load(bytes)) as LottieLoaded).handle;
      key = FrameCacheKey(
        contentHash: 'abc123',
        width: side,
        height: side,
        engineVersion: '1.0.0',
      );
    });
    tearDown(() async {
      memory.dispose();
      await engine.close();
    });

    LottieSource source({FrameCacheKey? cacheKey, int? frameCount}) =>
        LottieSource(
          handle,
          frameCount: frameCount ?? info.frameCount,
          cacheKey: cacheKey,
        );

    /// One job per frame, each into a slot of its own.
    List<FrameJob> jobs(Iterable<int> frames, LottieSource source) => [
      for (final frame in frames)
        FrameJob(
          slot: allocator.allocate(side, side)!,
          frame: frame,
          width: side,
          height: side,
          source: source,
        ),
    ];

    /// The pixels of [job]'s slot, row by row.
    List<int> pixels(FrameJob job) {
      final page = memory.page(job.slot.pageIndex, side: job.slot.pageSide);
      final left = job.slot.rect.left.toInt();
      final top = job.slot.rect.top.toInt();
      return [
        for (var y = 0; y < side; y++)
          for (var x = 0; x < side * 4; x++)
            page[((top + y) * 256 + left) * 4 + x],
      ];
    }

    LottieFrameRenderer renderer(FrameCache? cache) =>
        LottieFrameRenderer(engine: engine, memory: memory, cache: cache);

    test('the first pass renders and stores; the second restores and '
        'renders nothing', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      final r = renderer(cache);
      final first = jobs([0, 1, 2], source(cacheKey: key));
      final second = jobs([0, 1, 2], source(cacheKey: key));

      expect(await r.render(first, memory), [0, 1, 2]);
      expect(engine.rendered, 3);
      expect(engine.restored, 0);
      expect(await r.render(second, memory), [0, 1, 2]);

      expect(engine.rendered, 3, reason: 'nothing rendered again');
      expect(engine.restored, 3);
      for (var i = 0; i < 3; i++) {
        expect(pixels(second[i]), pixels(first[i]), reason: 'frame $i');
        expect(pixels(second[i]).any((b) => b != 0), isTrue);
      }
    });

    test('a batch of cached and fresh frames renders only the fresh, and '
        'answers in job order', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      final r = renderer(cache);
      await r.render(jobs([1, 2], source(cacheKey: key)), memory);
      engine
        ..rendered = 0
        ..restored = 0;

      final mixed = jobs([0, 1, 2, 3], source(cacheKey: key));
      final held = await r.render(mixed, memory);

      expect(held, [0, 1, 2, 3]);
      expect(engine.rendered, 2, reason: 'frames 0 and 3');
      expect(engine.restored, 2, reason: 'frames 1 and 2');
      expect(cache.has(key, 0), isTrue);
      expect(cache.has(key, 3), isTrue);
    });

    test('a fresh cache on the same directory restores without rendering '
        'after open', () async {
      final dir = Directory.systemTemp.createTempSync('lottie_renderer_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final slots = [
        for (var i = 0; i < info.frameCount; i++)
          allocator.allocate(side, side)!,
      ];
      List<FrameJob> pass() => [
        for (var i = 0; i < slots.length; i++)
          FrameJob(
            slot: slots[i],
            frame: i,
            width: side,
            height: side,
            source: source(cacheKey: key),
          ),
      ];
      final before = FrameCache(directory: dir);
      await renderer(before).render(pass(), memory);
      await before.dispose();
      final expected = [for (final job in pass()) pixels(job)];
      memory.page(0, side: 256).fillRange(0, 256 * 256 * 4, 0);
      engine
        ..rendered = 0
        ..restored = 0;

      // A new process, as far as the cache can tell: nothing in RAM.
      final after = FrameCache(directory: dir);
      addTearDown(after.dispose);
      final jobs = pass();
      final held = await renderer(after).render(jobs, memory);

      expect(held, hasLength(info.frameCount));
      expect(engine.rendered, 0);
      expect(engine.restored, info.frameCount);
      for (var i = 0; i < jobs.length; i++) {
        expect(pixels(jobs[i]), expected[i], reason: 'frame $i');
        expect(pixels(jobs[i]).any((b) => b != 0), isTrue);
      }
    });

    test('a corrupt entry is rendered instead, and the animation is '
        'dropped from the cache', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      for (var i = 0; i < info.frameCount; i++) {
        cache.put(
          key,
          i,
          Uint8List.fromList([9, 9, 9]),
          frameCount: info.frameCount,
        );
      }
      final job = jobs([3], source(cacheKey: key));

      final held = await renderer(cache).render(job, memory);

      expect(held, [0], reason: 'the frame is there, rendered');
      expect(engine.restored, 1, reason: 'the entry was tried');
      expect(engine.rendered, 1, reason: 'and the frame rendered after it');
      expect(pixels(job.single).any((b) => b != 0), isTrue);
      expect(
        cache.has(key, 4),
        isFalse,
        reason: 'the rest of the garbage went',
      );
      expect(
        cache.frame(key, 3),
        isNot(Uint8List.fromList([9, 9, 9])),
        reason: 'the rendered frame replaced the garbage',
      );
    });

    test('a key above the display cap bypasses the cache', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      final big = FrameCacheKey(
        contentHash: 'abc123',
        width: 600,
        height: 600,
        engineVersion: '1.0.0',
      );
      final r = renderer(cache);

      expect(await r.render(jobs([0], source(cacheKey: big)), memory), [0]);
      expect(await r.render(jobs([0], source(cacheKey: big)), memory), [0]);

      expect(engine.rendered, 2);
      expect(engine.restored, 0);
      expect(cache.has(big, 0), isFalse);
    });

    test('without a cache every frame renders, as before', () async {
      final r = renderer(null);

      await r.render(jobs([0, 1], source(cacheKey: key)), memory);
      await r.render(jobs([0, 1], source(cacheKey: key)), memory);

      expect(engine.rendered, 4);
      expect(engine.restored, 0);
    });

    test('a source without a key renders every time', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      final r = renderer(cache);

      await r.render(jobs([0], source()), memory);
      await r.render(jobs([0], source()), memory);

      expect(engine.rendered, 2);
    });

    test('a frame that did not render is not stored, nor reported', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      await engine.dispose(handle);

      final held = await renderer(
        cache,
      ).render(jobs([0], source(cacheKey: key)), memory);

      expect(held, isEmpty);
      expect(cache.has(key, 0), isFalse);
    });

    test('a frame outside the animation renders and is not stored', () async {
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);

      final held = await renderer(
        cache,
      ).render(jobs([info.frameCount + 5], source(cacheKey: key)), memory);

      expect(held, [0]);
      expect(await cache.open(key), isNull);
    });

    test('an engine without a codec renders, and stores nothing', () async {
      final bare = open(codec: null);
      addTearDown(bare.close);
      final bareHandle = ((await bare.load(bytes)) as LottieLoaded).handle;
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      final r = LottieFrameRenderer(engine: bare, memory: memory, cache: cache);

      final held = await r.render([
        FrameJob(
          slot: allocator.allocate(side, side)!,
          frame: 1,
          width: side,
          height: side,
          source: LottieSource(
            bareHandle,
            frameCount: info.frameCount,
            cacheKey: key,
          ),
        ),
      ], memory);

      expect(held, [0]);
      expect(cache.has(key, 1), isFalse);
    });

    test('a disposed cache is skipped, not an error', () async {
      final cache = FrameCache(directory: null);
      final r = renderer(cache);
      await cache.dispose();

      final held = await r.render(jobs([0], source(cacheKey: key)), memory);

      expect(held, [0]);
      expect(engine.rendered, 1);
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
    test('30 rendered frames restore from the cache pixel for pixel', () async {
      const side = 48;
      const count = 30;
      final engine = CountingLottieEngine(
        InProcessLottieEngine(
          NativeLottieBinding.probe(),
          codec: NativeLottieFrameCodec.probe(),
        ),
      );
      addTearDown(engine.close);
      final memory = NativeFramePageMemory();
      addTearDown(memory.dispose);
      final loaded =
          await engine.load(Uint8List.fromList(utf8.encode(_fixture)))
              as LottieLoaded;
      final key = FrameCacheKey(
        contentHash: 'fixture',
        width: side,
        height: side,
        engineVersion: LottieNativeVersion.engine,
      );
      final cache = FrameCache(directory: null);
      addTearDown(cache.dispose);
      final renderer = LottieFrameRenderer(
        engine: engine,
        memory: memory,
        cache: cache,
      );
      final allocator = FrameSlotAllocator(
        pageSideFor: (_) => 512,
        budgetBytes: 512 * 512 * 4,
        sizeClasses: const [64],
      );
      final slots = [
        for (var i = 0; i < count * 2; i++) allocator.allocate(side, side)!,
      ];
      List<FrameJob> pass(int from) => [
        for (var i = 0; i < count; i++)
          FrameJob(
            slot: slots[from + i],
            frame: i,
            width: side,
            height: side,
            source: LottieSource(
              loaded.handle,
              frameCount: loaded.info.frameCount,
              cacheKey: key,
            ),
          ),
      ];
      List<int> pixels(FrameJob job) {
        final page = memory.page(job.slot.pageIndex, side: job.slot.pageSide);
        final left = job.slot.rect.left.toInt();
        final top = job.slot.rect.top.toInt();
        return [
          for (var y = 0; y < side; y++)
            for (var x = 0; x < side * 4; x++)
              page[((top + y) * 512 + left) * 4 + x],
        ];
      }

      final rendered = pass(0);
      await renderer.render(rendered, memory);
      final restored = pass(count);
      final held = await renderer.render(restored, memory);

      expect(held, hasLength(count));
      expect(engine.rendered, count, reason: 'the second pass drew nothing');
      expect(engine.restored, count);
      for (var i = 0; i < count; i++) {
        expect(pixels(restored[i]), pixels(rendered[i]), reason: 'frame $i');
      }
      expect(
        {for (final job in rendered) pixels(job).join(',')}.length,
        greaterThan(1),
        reason: 'the frames differ, so equality means something',
      );
    });

    _runContract(
      NativeLottieBinding.probe,
      Uint8List.fromList(utf8.encode(_fixture)),
      Uint8List.fromList(utf8.encode('not a lottie file')),
      frameStep: 20,
    );
  });
}
