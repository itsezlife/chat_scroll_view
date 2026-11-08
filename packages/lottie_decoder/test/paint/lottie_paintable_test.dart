import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

const _budget = 2 * 128 * 128 * 4;

ui.Image _image([int side = 4]) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

Future<ui.Image> _upload(Uint8List pixels, int side) => Future.value(_image());

/// Keeps what is drawn, as the arguments of each `drawImageRect`.
final class _RecordingCanvas implements ui.Canvas {
  final List<({ui.Image image, Rect src, Rect dst, double alpha})> draws = [];

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, ui.Paint paint) =>
      draws.add((image: image, src: src, dst: dst, alpha: paint.color.a));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Answers every job as failed, and counts the jobs it was given.
final class _FailingRenderer implements FrameRenderer {
  int jobs = 0;

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    this.jobs += jobs.length;
    return const [];
  }
}

/// Keeps the source of every job, and renders them all.
final class _SourceRecordingRenderer implements FrameRenderer {
  final List<Object> sources = [];

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    sources.addAll([for (final job in jobs) job.source]);
    _touch(jobs, memory);
    return [for (var i = 0; i < jobs.length; i++) i];
  }
}

void main() {
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );
  const handle = LottieHandle(1);
  const frame = Duration(milliseconds: 33); // a little over one frame at 30

  late FakeFrameRenderer renderer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late LottieFrameScheduler scheduler;
  var now = Duration.zero;

  LottieFrameScheduler build(FrameRenderer r, {int budget = _budget}) =>
      LottieFrameScheduler(
        atlas: FrameAtlas<Object>(
          renderer: r,
          memory: ListFramePageMemory(),
          budgetBytes: budget,
          sizeClasses: const [64],
          upload: _upload,
        ),
        clock: clock,
        startTimer: timers.start,
      );

  void tick() {
    now += const Duration(milliseconds: 16);
    ticks.tick(now);
  }

  LottieAnimationPaintable make({
    Object key = 'a',
    ui.Image? still,
    VoidCallback? onDispose,
    FrameCacheKey? cacheKey,
  }) => LottieAnimationPaintable(
    key: key,
    handle: handle,
    cacheKey: cacheKey,
    info: info,
    firstFrame: still ?? _image(8),
    scheduler: scheduler,
    renderEdge: 48,
    onDispose: onDispose,
  );

  AssetPaintContext at(
    int ms, {
    bool loop = true,
    AssetRestFrame rest = AssetRestFrame.first,
    bool animate = true,
    double opacity = 1,
  }) => AssetPaintContext(
    time: Duration(milliseconds: ms),
    loop: loop,
    restFrame: rest,
    animate: animate,
    opacity: opacity,
  );

  const box = Rect.fromLTWH(0, 0, 100, 50);

  /// Paints at [ms], lets the clock tick and the batch finish.
  Future<_RecordingCanvas> paintAndSettle(
    LottieAnimationPaintable p,
    AssetPaintContext context,
  ) async {
    final canvas = _RecordingCanvas();
    p.paint(canvas, box, context);
    tick();
    await pumpEventQueue();
    return canvas;
  }

  setUp(() {
    now = Duration.zero;
    renderer = FakeFrameRenderer();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = build(renderer);
  });
  tearDown(() {
    scheduler.dispose();
    clock.dispose();
  });

  group('LottieStillPaintable', () {
    test('draws the image contain-fitted, with the opacity', () {
      final p = LottieStillPaintable(_image(8));
      final canvas = _RecordingCanvas();

      p.paint(canvas, box, at(0, opacity: 0.5));

      expect(canvas.draws, hasLength(1));
      expect(canvas.draws.single.dst, const Rect.fromLTWH(25, 0, 50, 50));
      expect(canvas.draws.single.src, const Rect.fromLTWH(0, 0, 8, 8));
      expect(canvas.draws.single.alpha, closeTo(0.5, 0.01));
      expect(p.isAnimated, isFalse);
      expect(p.sprite, isNull);
      expect(p.isHolding, isFalse);
      expect(p.restart(), isFalse);
    });

    test('dispose disposes the image', () {
      final image = _image();
      LottieStillPaintable(image).dispose();
      expect(image.debugDisposed, isTrue);
    });
  });

  group('LottieAnimationPaintable', () {
    test('dispose runs onDispose once, so its owner frees the handle', () {
      var disposed = 0;
      final p = make(onDispose: () => disposed++);

      p.dispose();
      p.dispose();

      expect(disposed, 1);
    });

    test('is animated and paints itself', () {
      final p = make();
      expect(p.isAnimated, isTrue);
      expect(p.sprite, isNull);
    });

    test('asks for the frame after the one its time names', () async {
      final p = make();
      await paintAndSettle(p, at(5000));
      // 200 ms after the first paint is frame 6 at 30 fps; one ahead is 7.
      await paintAndSettle(p, at(5000 + 200));

      expect(renderer.batches, [
        [1],
        [7],
      ]);
    });

    test('renders through a source carrying its handle, key and frame '
        'count', () async {
      final recording = _SourceRecordingRenderer();
      scheduler.dispose();
      scheduler = build(recording);
      final cacheKey = FrameCacheKey(
        contentHash: 'abc',
        width: 48,
        height: 48,
        engineVersion: '1.0.0',
      );

      await paintAndSettle(make(cacheKey: cacheKey), at(0));

      expect(recording.sources, [
        LottieSource(handle, cacheKey: cacheKey, frameCount: info.frameCount),
      ]);
    });

    test('wraps around the frame count while looping', () async {
      final p = make();
      await paintAndSettle(p, at(0));
      await paintAndSettle(p, at(400)); // frame 12 -> 2, ahead 3

      expect(renderer.batches.last, [3]);
    });

    test('draws the still until a frame arrives, then the sprite', () async {
      final still = _image(8);
      final p = make(still: still);

      final first = await paintAndSettle(p, at(0));
      expect(first.draws.single.image, same(still));

      final second = await paintAndSettle(p, at(frame.inMilliseconds));
      final draw = second.draws.single;
      expect(draw.image, isNot(same(still)));
      expect(draw.src.size, const Size(48, 48));
      expect(draw.dst, const Rect.fromLTWH(25, 0, 50, 50));
    });

    test('keeps drawing the last sprite while a frame is late', () async {
      final p = make();
      await paintAndSettle(p, at(0));
      renderer.pause();
      await paintAndSettle(p, at(100));

      final canvas = await paintAndSettle(p, at(200));

      expect(canvas.draws.single.src.size, const Size(48, 48));
      renderer.resume();
    });

    test('does not ask again for the frame it already asked for', () async {
      final p = make();
      await paintAndSettle(p, at(100));
      await paintAndSettle(p, at(100));
      await paintAndSettle(p, at(100));

      expect(renderer.batches, hasLength(1));
    });

    test('holds the first frame after one pass when not looping', () async {
      final p = make();
      await paintAndSettle(p, at(0, loop: false));
      expect(p.isHolding, isFalse);

      await paintAndSettle(p, at(400, loop: false));
      expect(p.isHolding, isTrue);
      expect(renderer.batches.last, [0]);

      await paintAndSettle(p, at(500, loop: false));
      expect(renderer.batches, hasLength(2), reason: 'holding asks nothing');
    });

    test('holds the last frame with restFrame last', () async {
      final p = make();
      await paintAndSettle(p, at(0, loop: false, rest: AssetRestFrame.last));
      await paintAndSettle(p, at(400, loop: false, rest: AssetRestFrame.last));

      expect(p.isHolding, isTrue);
      expect(renderer.batches.last, [9]);
    });

    test('restart plays another pass from the first frame', () async {
      final p = make();
      expect(p.restart(), isFalse, reason: 'nothing to restart yet');
      await paintAndSettle(p, at(0, loop: false));
      await paintAndSettle(p, at(400, loop: false));
      expect(p.isHolding, isTrue);

      expect(p.restart(), isTrue);
      expect(p.isHolding, isFalse);
      await paintAndSettle(p, at(450, loop: false));
      await paintAndSettle(p, at(450 + 100, loop: false)); // frame 3

      expect(renderer.batches.last, [4]);
      expect(p.restart(), isFalse, reason: 'a pass in progress is not rewound');
    });

    test('a looping paint resumes a holding paintable', () async {
      final p = make();
      await paintAndSettle(p, at(0, loop: false));
      await paintAndSettle(p, at(400, loop: false));

      await paintAndSettle(p, at(430));

      expect(p.isHolding, isFalse);
    });

    test('continues where it stopped after a pause', () async {
      final p = make();
      await paintAndSettle(p, at(1000));
      await paintAndSettle(p, at(1100)); // frame 3, ahead 4
      expect(renderer.batches.last, [4]);

      // The clock stood still, then jumped by the length of the pause.
      await paintAndSettle(p, at(1100 + 60000));
      expect(renderer.batches, hasLength(2), reason: 'same frame as before');

      await paintAndSettle(p, at(1100 + 60000 + 100)); // 100 ms on: frame 6
      expect(renderer.batches.last, [7]);
    });

    test('a paint that does not animate asks for nothing', () async {
      final still = _image(8);
      final p = make(still: still);

      final canvas = await paintAndSettle(p, at(0, animate: false));

      expect(renderer.batches, isEmpty);
      expect(scheduler.leaseCount, 0);
      expect(canvas.draws.single.image, same(still));
    });

    test('shows its still and does not throw when the pool is full', () async {
      scheduler.dispose();
      scheduler = build(renderer, budget: 128 * 128 * 4);
      for (var i = 0; i < 4; i++) {
        scheduler.acquire('held$i', 'src', 48, 48);
      }
      final still = _image(8);
      final p = make(still: still);

      final canvas = await paintAndSettle(p, at(0));

      expect(canvas.draws.single.image, same(still));
      expect(renderer.batches, isEmpty);
    });

    test('acquires again after the sweep released its lease', () async {
      final p = make();
      await paintAndSettle(p, at(0));
      await paintAndSettle(p, at(frame.inMilliseconds));
      timers.elapse(const Duration(seconds: 1));
      timers.elapse(const Duration(seconds: 1));
      expect(scheduler.leaseCount, 0);

      await paintAndSettle(p, at(100));

      expect(scheduler.leaseCount, 1);
    });

    test(
      'a repaint in a pause longer than the idle period keeps the frame',
      () async {
        final still = _image(8);
        final p = make(still: still);
        await paintAndSettle(p, at(0));
        final before = await paintAndSettle(p, at(frame.inMilliseconds));
        final rendered = before.draws.single.image;
        expect(rendered, isNot(same(still)), reason: 'a frame is on screen');

        // The clock stands still, but the sweep timer is real time by design.
        clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);
        for (var i = 0; i < 4; i++) {
          timers.elapse(const Duration(seconds: 1));
        }
        final canvas = _RecordingCanvas();
        p.paint(canvas, box, at(frame.inMilliseconds));

        expect(canvas.draws.single.image, same(rendered));
      },
    );

    test('stops asking after a failed frame and keeps its still', () async {
      scheduler.dispose();
      final failing = _FailingRenderer();
      scheduler = build(failing);
      final still = _image(8);
      final p = make(still: still);

      await paintAndSettle(p, at(0));
      expect(failing.jobs, 1);
      final canvas = await paintAndSettle(p, at(200));
      await paintAndSettle(p, at(400));

      expect(failing.jobs, 1);
      expect(canvas.draws.single.image, same(still));
    });

    group('as a sprite', () {
      /// Advances at [ms] without painting, lets the clock tick and the batch
      /// finish.
      Future<void> advanceAndSettle(
        LottieAnimationPaintable p,
        AssetPaintContext context,
      ) async {
        p.advancePlayback(context);
        tick();
        await pumpEventQueue();
      }

      test(
        'has no sprite until a frame is rendered, so the still paints',
        () async {
          final p = make();
          expect(p.sprite, isNull);

          await advanceAndSettle(p, at(0));
          expect(p.sprite, isNotNull, reason: 'the frame landed');

          final fresh = make(key: 'b');
          expect(fresh.sprite, isNull);
          fresh.dispose();
        },
      );

      test(
        'the sprite is the leased frame, cut at the rendered size',
        () async {
          final p = make();

          await advanceAndSettle(p, at(0));

          expect(p.sprite!.source.size, const Size(48, 48));
        },
      );

      test(
        'advancing without painting asks for the frames playback names',
        () async {
          final p = make();
          await advanceAndSettle(p, at(5000));
          await advanceAndSettle(p, at(5000 + 200));

          expect(renderer.batches, [
            [1],
            [7],
          ]);
        },
      );

      test('advance then paint in one pass asks once', () async {
        final p = make();
        await advanceAndSettle(p, at(100));
        final canvas = _RecordingCanvas();
        p.paint(canvas, box, at(100));
        tick();
        await pumpEventQueue();

        expect(renderer.batches, hasLength(1));
      });

      test(
        'advancing a paint that does not animate asks for nothing',
        () async {
          final p = make();

          await advanceAndSettle(p, at(0, animate: false));

          expect(renderer.batches, isEmpty);
          expect(scheduler.leaseCount, 0);
          expect(p.sprite, isNull);
        },
      );

      test('keeps the last sprite while a frame is late', () async {
        final p = make();
        await advanceAndSettle(p, at(0));
        renderer.pause();
        await advanceAndSettle(p, at(100));

        expect(p.sprite, isNotNull);
        renderer.resume();
      });

      test('has no sprite after the renderer failed it', () async {
        scheduler.dispose();
        scheduler = build(_FailingRenderer());
        final p = make();

        await advanceAndSettle(p, at(0));
        await advanceAndSettle(p, at(200));

        expect(p.sprite, isNull);
      });

      test('has none once disposed', () async {
        final p = make();
        await advanceAndSettle(p, at(0));

        p.dispose();

        expect(p.sprite, isNull);
      });
    });

    test('dispose releases the lease and the still', () async {
      final still = _image(8);
      final p = make(still: still);
      await paintAndSettle(p, at(0));
      expect(scheduler.leaseCount, 1);

      p.dispose();
      p.dispose();

      expect(scheduler.leaseCount, 0);
      expect(still.debugDisposed, isTrue);
    });

    group('texture', () {
      late FakeFrameTextureHost host;
      late FrameTexturePool pool;

      setUp(() async {
        scheduler.dispose();
        host = FakeFrameTextureHost();
        pool = FrameTexturePool(host: host, sizeClasses: const [64]);
        await pool.warm(64, 1);
        scheduler = LottieFrameScheduler(
          atlas: FrameAtlas<Object>(
            renderer: renderer,
            memory: ListFramePageMemory(),
            budgetBytes: _budget,
            sizeClasses: const [64],
            upload: _upload,
          ),
          clock: clock,
          textures: pool,
          textureWriter: FakeTextureFrameWriter(),
          startTimer: timers.start,
        );
      });
      tearDown(() => pool.dispose());

      Future<void> advanceAndSettle(
        LottieAnimationPaintable p,
        AssetPaintContext context,
      ) async {
        p.advancePlayback(context);
        tick();
        await pumpEventQueue();
      }

      test('is null before the first advance and until a frame is posted', () {
        final p = make();
        expect(p.texture, isNull);

        p.advancePlayback(at(0));

        expect(p.texture, isNull);
      });

      test('is the leased texture once a frame was posted, and the still is '
          'not drawn over it', () async {
        final p = make();
        await advanceAndSettle(p, at(0));

        expect(
          p.texture,
          AssetTexture(id: host.liveIds.single, width: 64, height: 64),
        );
        expect(p.sprite, isNull);
        expect(renderer.batches, isEmpty, reason: 'no page for it');
      });

      test('a surface that only paints keeps drawing sprites', () async {
        final p = make();
        final canvas = await paintAndSettle(p, at(0));
        expect(canvas.draws.single.image.width, 8, reason: 'the still');

        final next = await paintAndSettle(p, at(33));

        expect(p.texture, isNull);
        expect(next.draws.single.src.width, 48, reason: 'a sprite');
      });

      test('goes with the lease on dispose', () async {
        final p = make();
        await advanceAndSettle(p, at(0));

        p.dispose();

        expect(p.texture, isNull);
        expect(pool.idleTextures, 1);
      });
    });
  });

  group('over the in-process engine', () {
    Future<
      ({
        LottieAnimationPaintable paintable,
        LottieFrameScheduler scheduler,
        FakeLottieBinding binding,
      })
    >
    open({required bool fails}) async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final binding = FakeLottieBinding()
        ..accept(bytes, info)
        ..renderFails = fails;
      final engine = InProcessLottieEngine(binding);
      final loaded = (await engine.load(bytes)) as LottieLoaded;
      final memory = NativeFramePageMemory();
      final real = LottieFrameScheduler(
        atlas: FrameAtlas<Object>(
          renderer: LottieFrameRenderer(engine: engine, memory: memory),
          memory: memory,
          budgetBytes: _budget,
          sizeClasses: const [64],
          upload: _upload,
        ),
        clock: clock,
        startTimer: timers.start,
      );
      addTearDown(() async {
        real.dispose();
        memory.dispose();
        await engine.close();
      });
      final paintable = LottieAnimationPaintable(
        key: 'real',
        handle: loaded.handle,
        info: loaded.info,
        firstFrame: _image(8),
        scheduler: real,
        renderEdge: 48,
      );
      return (paintable: paintable, scheduler: real, binding: binding);
    }

    test('draws a sprite once the engine rendered the frame', () async {
      final o = await open(fails: false);
      scheduler = o.scheduler;
      final p = o.paintable;
      await paintAndSettle(p, at(0));

      final canvas = await paintAndSettle(p, at(100));

      expect(canvas.draws.single.src.size, const Size(48, 48));
    });

    test('keeps the still when the engine fails the job', () async {
      final o = await open(fails: true);
      scheduler = o.scheduler;
      final p = o.paintable;
      await paintAndSettle(p, at(0));

      await paintAndSettle(p, at(100));
      final canvas = await paintAndSettle(p, at(200));

      expect(canvas.draws.single.src, const Rect.fromLTWH(0, 0, 8, 8));
    });
  });
}

/// Makes the pages the jobs name, as a renderer that really wrote them would.
void _touch(List<FrameJob> jobs, FramePageMemory memory) {
  for (final job in jobs) {
    memory.page(job.slot.pageIndex, side: job.slot.pageSide);
  }
}
