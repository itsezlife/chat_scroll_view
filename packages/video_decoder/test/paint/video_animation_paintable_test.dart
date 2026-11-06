import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

const _info = VideoInfo(
  width: 16,
  height: 16,
  duration: Duration(milliseconds: 100),
  frameRate: 30,
  hasAlpha: true,
);

ui.Image _solid(int rgba, {int side = 16}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    ui.Paint()..color = ui.Color(rgba),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

/// Keeps what is drawn, as the arguments of each `drawImageRect`.
final class _RecordingCanvas implements ui.Canvas {
  final List<({ui.Image image, Rect src, Rect dst, double alpha})> draws = [];

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, ui.Paint paint) =>
      draws.add((image: image, src: src, dst: dst, alpha: paint.color.a));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  late FakeVideoEngine engine;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late VideoFrameScheduler scheduler;
  late VideoClip clip;
  var now = Duration.zero;
  var disposed = 0;

  Future<void> tick() async {
    now += const Duration(milliseconds: 16);
    ticks.tick(now);
    await pumpEventQueue();
  }

  VideoFrameScheduler build({int budget = 32 * 1024 * 1024}) =>
      VideoFrameScheduler(
        engine: engine,
        atlas: VideoFrameAtlas.create(
          budgetBytes: budget,
          upload: (pixels, side) async => _solid(0xFF000000, side: 4),
        ),
        clock: clock,
        startTimer: timers.start,
      );

  VideoAnimationPaintable paintable({Object key = 'a'}) =>
      VideoAnimationPaintable(
        key: key,
        clip: clip,
        firstFrame: _solid(0xFF00FF00),
        scheduler: scheduler,
        onDispose: () => disposed++,
      );

  /// Paints at [ms] of the shared clock, as a surface would each frame.
  Future<_RecordingCanvas> paintAt(
    VideoAnimationPaintable p,
    int ms, {
    bool loop = true,
    AssetRestFrame rest = AssetRestFrame.first,
  }) async {
    final canvas = _RecordingCanvas();
    p.paint(
      canvas,
      const Rect.fromLTWH(0, 0, 16, 16),
      AssetPaintContext(
        time: Duration(milliseconds: ms),
        loop: loop,
        restFrame: rest,
      ),
    );
    await tick();
    return canvas;
  }

  setUp(() async {
    now = Duration.zero;
    disposed = 0;
    engine = FakeVideoEngine()..accept(bytes, _info, frameCount: 3);
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = build();
    clip =
        ((await engine.open(bytes, width: 16, height: 16)) as VideoClipOpened)
            .clip;
  });
  tearDown(() {
    scheduler.dispose();
    clock.dispose();
  });

  group('VideoAnimationPaintable', () {
    test('is animated and paints its first frame until one is drawn', () async {
      final p = paintable();
      addTearDown(p.dispose);

      expect(p.isAnimated, isTrue);
      expect(p.sprite, isNull);
      final first = _RecordingCanvas();
      p.paint(
        first,
        const Rect.fromLTWH(0, 0, 16, 16),
        const AssetPaintContext(),
      );
      expect(first.draws.single.image.width, 16);
    });

    test('draws the lease sprite once a frame exists', () async {
      final p = paintable();
      addTearDown(p.dispose);
      for (var ms = 0; ms < 200; ms += 20) {
        await paintAt(p, ms);
      }

      expect(p.sprite, isNotNull);
      final canvas = await paintAt(p, 220);
      // The page, not the still: a 4 px stub page against a 16 px still.
      expect(canvas.draws.single.image.width, 4);
      expect(canvas.draws.single.src.size, const Size(16, 16));
    });

    test('cover fills the cell with the still, cropping the overflow', () {
      final p = paintable();
      addTearDown(p.dispose);
      final canvas = _RecordingCanvas();
      const cell = Rect.fromLTWH(0, 0, 32, 16);

      p.paint(canvas, cell, const AssetPaintContext(fit: AssetFit.cover));

      // A 16 x 16 still in a 32 x 16 cell: the whole width, the middle half.
      expect(canvas.draws.single.dst, cell);
      expect(canvas.draws.single.src, const Rect.fromLTWH(0, 4, 16, 8));
    });

    test('contain keeps the still whole with bars', () {
      final p = paintable();
      addTearDown(p.dispose);
      final canvas = _RecordingCanvas();

      p.paint(
        canvas,
        const Rect.fromLTWH(0, 0, 32, 16),
        const AssetPaintContext(),
      );

      expect(canvas.draws.single.src, const Rect.fromLTWH(0, 0, 16, 16));
      expect(canvas.draws.single.dst, const Rect.fromLTWH(8, 0, 16, 16));
    });

    test('cover crops the lease sprite on its page', () async {
      final p = paintable();
      addTearDown(p.dispose);
      for (var ms = 0; ms < 200; ms += 20) {
        await paintAt(p, ms);
      }
      final sprite = p.sprite!;
      final canvas = _RecordingCanvas();
      const cell = Rect.fromLTWH(0, 0, 32, 16);

      p.paint(canvas, cell, const AssetPaintContext(fit: AssetFit.cover));

      final draw = canvas.draws.single;
      expect(draw.image, same(sprite.page));
      expect(draw.dst, cell);
      expect(draw.src.width, sprite.source.width);
      expect(draw.src.height, closeTo(sprite.source.height / 2, 1e-9));
      expect(draw.src.center, sprite.source.center);
    });

    test('a step over the resume gap adds no played time', () async {
      final p = paintable();
      addTearDown(p.dispose);
      for (var ms = 0; ms <= 40; ms += 20) {
        await paintAt(p, ms, loop: false);
      }
      // The clock stood still while paused and then jumped by a minute.
      await paintAt(p, 60040, loop: false);
      await paintAt(p, 60060, loop: false);

      // 60 ms played of a 100 ms clip: the pass is not over.
      expect(p.isHolding, isFalse);
    });

    test(
      'a pass that does not loop holds the rest frame, and restarts',
      () async {
        final p = paintable();
        addTearDown(p.dispose);
        for (var ms = 0; ms <= 400; ms += 25) {
          await paintAt(p, ms, loop: false);
        }

        expect(p.isHolding, isTrue);
        expect(p.restart(), isTrue);
        expect(p.isHolding, isFalse);
        expect(
          p.restart(),
          isFalse,
          reason: 'a pass in progress is not rewound',
        );
      },
    );

    test(
      'a holding pass with the first frame at rest shows the still',
      () async {
        final p = paintable();
        addTearDown(p.dispose);
        for (var ms = 0; ms <= 400; ms += 25) {
          await paintAt(p, ms, loop: false);
        }

        final canvas = await paintAt(p, 450, loop: false);

        expect(p.sprite, isNull);
        expect(canvas.draws.single.image.width, 16);
      },
    );

    test('with the pool full it keeps painting the still', () async {
      scheduler.dispose();
      scheduler = build(budget: 128 * 128 * 4);
      final others = [
        for (var i = 0; i < 4; i++) scheduler.acquire('o$i', clip),
      ];
      expect(others.whereType<VideoFrameLease>(), hasLength(4));
      final p = paintable();
      addTearDown(p.dispose);

      for (var ms = 0; ms < 100; ms += 20) {
        await paintAt(p, ms);
      }

      expect(p.sprite, isNull);
    });

    test('dispose frees the lease, the still and the clip once', () async {
      final p = paintable();
      for (var ms = 0; ms < 100; ms += 20) {
        await paintAt(p, ms);
      }

      p
        ..dispose()
        ..dispose();

      expect(disposed, 1);
      expect(scheduler.leaseCount, 0);
      expect(scheduler.bufferedBytes, 0);
    });

    test('a failed lease is never asked again and the still stays', () async {
      await engine.close(clip);
      final p = paintable();
      addTearDown(p.dispose);
      for (var ms = 0; ms < 100; ms += 20) {
        await paintAt(p, ms);
      }

      expect(p.sprite, isNull);
      final canvas = await paintAt(p, 120);
      expect(canvas.draws.single.image.width, 16);
    });

    test('keeps alpha premultiplied BGRA to the screen', () async {
      scheduler.dispose();
      // The real page upload: the pages are BGRA and must be read as such.
      scheduler = VideoFrameScheduler(
        engine: engine,
        atlas: VideoFrameAtlas.create(),
        clock: clock,
        startTimer: timers.start,
      );
      final p = paintable();
      addTearDown(p.dispose);
      for (var ms = 0; ms <= 80; ms += 20) {
        await paintAt(p, ms);
      }
      Future<List<int>> centre() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 16, 16),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF),
          );
        p.paint(
          canvas,
          const Rect.fromLTWH(0, 0, 16, 16),
          const AssetPaintContext(time: Duration(milliseconds: 100)),
        );
        final picture = recorder.endRecording();
        final image = picture.toImageSync(16, 16);
        picture.dispose();
        final rgba = (await image.toByteData())!;
        image.dispose();
        const at = (8 * 16 + 8) * 4;
        return [for (var c = 0; c < 4; c++) rgba.getUint8(at + c)];
      }

      // Real image uploads complete outside the fake event loop, and on a
      // loaded runner later than any fixed wait. The clip loops, so keep
      // painting until frame 2's upload is the one on screen.
      var pixel = <int>[];
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await paintAt(p, 90);
        pixel = await centre();
        if ((pixel[1] - 71).abs() <= 2) break;
      }

      expect(p.sprite, isNotNull);
      // The fake's frame 2 is B 32, G 16, R 0 under alpha 200. Over white
      // each channel adds the 55 the alpha lets through: R 55, G 71, B 87.
      expect(pixel, [closeTo(55, 2), closeTo(71, 2), closeTo(87, 2), 255]);
    });
  });
}
