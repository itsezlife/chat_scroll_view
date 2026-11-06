/// Animated leaves on screen: the Panel Catalog Viewport draws the frame of an
/// animation from its page like a baked glyph, in one batched draw per page,
/// instead of one image draw per cell.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource] and
/// a real [AssetCacheScope] over a [FakeAssetProducer], whose paintables expose
/// a sprite once they are advanced. What is observed is what the viewport asks
/// its canvas to draw (a recording canvas passed to `paint`): atlas draws, image
/// draws, where each sprite lands, and what the paintables were asked.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/recording_canvas.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 640 px viewport: 15 rows
// fit, so 60 leaves are all on screen. A sticker fills its cell: a 40 px box.
const _span = 4;
const _leaves = 60;
const _box = 40.0;
const _theme = PanelCatalogThemeData.light;

ui.Image _page() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(8, 8);
  picture.dispose();
  return image;
}

CatalogLeaf _sticker(int i, {bool animated = true}) => CatalogLeaf.document(
  'sticker-$i',
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.still,
  animated: animated,
);

/// An animation that draws its frame the way the Lottie paintable does: its
/// own image draw in [paint], or, once it exposes [sprite], the page sprite for
/// a surface that batches. With [exposesSprite] false it is the paintable
/// before it had a sprite, which is the baseline of the draw-op count.
final class _FramePaintable extends AssetPaintable {
  _FramePaintable(this._sprite, {required this.exposesSprite});

  final AtlasSprite _sprite;
  final bool exposesSprite;

  @override
  AtlasSprite? get sprite => exposesSprite ? _sprite : null;

  @override
  bool get isAnimated => true;

  @override
  bool get isHolding => false;

  @override
  bool restart() => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) =>
      canvas.drawImageRect(_sprite.page, _sprite.source, rect, Paint());

  @override
  void dispose() {}
}

/// Answers every attach at once with a [_FramePaintable] on one of [pages].
final class _FrameProducer implements AssetProducer {
  _FrameProducer(this.pages, {required this.exposesSprite});

  final List<ui.Image> pages;
  final bool exposesSprite;
  int _made = 0;

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final page = _made++ % pages.length;
    progress.advance(
      AssetStage.full,
      _FramePaintable(
        AtlasSprite(
          pageIndex: page,
          page: pages[page],
          source: const Rect.fromLTWH(0, 0, 48, 48),
        ),
        exposesSprite: exposesSprite,
      ),
      bytes: 100,
      tier: AssetTier.animated,
    );
    return _NoTask();
  }
}

final class _NoTask implements AssetTask {
  @override
  void cancel() {}
}

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late AssetCacheScope scope;
  late List<ui.Image> pages;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    scope = AssetCacheScope(producer: producer, clock: clock);
    pages = [_page(), _page(), _page()];
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
    clock.dispose();
    for (final page in pages) {
      page.dispose();
    }
  });

  Future<void> pumpViewport(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: _theme,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 640,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: scope,
                controller: controller,
                spanCount: _span,
                cellExtent: 40,
                headerExtent: 24,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  RenderPanelCatalog render(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  AtlasSprite sprite(
    int page, {
    int pageIndex = 0,
    Size size = const Size(48, 48),
  }) => AtlasSprite(
    pageIndex: pageIndex,
    page: pages[page],
    source: Offset.zero & size,
  );

  /// Every attach answered at once with an animated paintable whose frame
  /// lands on its first advance, on page `i % pageCount`.
  List<FakeAssetPaintable> answerAll({
    int pageCount = 3,
    Size size = const Size(48, 48),
    List<Duration> frames = const [],
    int? sameIndex,
    Set<int> noFrame = const {},
  }) {
    final made = <FakeAssetPaintable>[];
    producer.onProduce = (attempt) {
      final paintable = attempt.advance(
        AssetStage.full,
        animated: true,
        frames: frames,
      );
      final page = made.length % pageCount;
      if (!noFrame.contains(made.length)) {
        paintable.spriteOnAdvance = sprite(
          page,
          pageIndex: sameIndex ?? page,
          size: size,
        );
      }
      made.add(paintable);
    };
    return made;
  }

  Future<void> pumpAnimated(WidgetTester tester, {int count = _leaves}) async {
    snapshots.replaceSections([
      CatalogSection(
        id: 'a',
        title: 'A',
        leaves: [for (var i = 0; i < count; i++) _sticker(i)],
      ),
    ]);
    await pumpViewport(tester);
  }

  group('batching', () {
    testWidgets('animated cells over P pages are P atlas draws and no image '
        'draw', (tester) async {
      final made = answerAll();
      await pumpAnimated(tester);

      final canvas = paintOnce(tester);

      expect(made, hasLength(_leaves));
      expect(canvas.atlasDraws, hasLength(3));
      expect(canvas.atlasDraws.map((d) => d.sprites), everyElement(20));
      expect(canvas.imageDraws, 0);
      for (final paintable in made) {
        expect(paintable.paints, isEmpty, reason: 'drawn by the batch');
      }
    });

    testWidgets('pages numbered alike but different images stay apart', (
      tester,
    ) async {
      answerAll(sameIndex: 0);
      await pumpAnimated(tester);

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws, hasLength(3));
      expect(canvas.atlasDraws.map((d) => d.image).toSet(), containsAll(pages));
    });

    testWidgets('a cell without a frame yet paints itself, the rest batch', (
      tester,
    ) async {
      final made = answerAll(noFrame: {0});
      await pumpAnimated(tester, count: 8);

      final canvas = paintOnce(tester);

      expect(made.first.paints, hasLength(2), reason: 'pump and paint');
      expect(canvas.atlasDraws.fold<int>(0, (n, d) => n + d.sprites), 7);
    });
  });

  group('playback', () {
    testWidgets('every animated cell is advanced once per pass, before its '
        'sprite is read', (tester) async {
      final made = answerAll();
      await pumpAnimated(tester);

      final before = made.first.advances.length;
      paintOnce(tester);
      paintOnce(tester);

      for (final paintable in made) {
        expect(paintable.advances, hasLength(before + 2));
      }
      // The sprite only exists after an advance: batched cells prove the hook
      // ran first.
      expect(paintOnce(tester).atlasDraws, isNotEmpty);
    });

    testWidgets('a cell that is not animated is not advanced', (tester) async {
      final made = <FakeAssetPaintable>[];
      producer.onProduce = (attempt) =>
          made.add(attempt.advance(AssetStage.full));
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [for (var i = 0; i < 4; i++) _sticker(i, animated: false)],
        ),
      ]);
      await pumpViewport(tester);

      paintOnce(tester);

      for (final paintable in made) {
        expect(paintable.advances, isEmpty);
      }
    });

    testWidgets('frames advance with the clock while batched', (tester) async {
      final made = answerAll(
        frames: List.filled(10, const Duration(milliseconds: 100)),
      );
      await pumpAnimated(tester, count: 4);

      var now = Duration.zero;
      for (var i = 0; i < 5; i++) {
        ticks.tick(now);
        paintOnce(tester);
        now += const Duration(milliseconds: 100);
      }

      expect(made.first.frameShown, greaterThan(2));
      expect(made.first.paints, isEmpty);
    });

    testWidgets('no fling-time ticks with batching on, and the last frame '
        'stays drawn', (tester) async {
      answerAll();
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [for (var i = 0; i < 400; i++) _sticker(i)],
        ),
      ]);
      await pumpViewport(tester);
      expect(ticks.isRunning, isTrue);
      expect(paintOnce(tester).atlasDraws, isNotEmpty);

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -300),
        2000,
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(render(tester).isFlinging, isTrue);
      expect(ticks.isRunning, isFalse);
      expect(paintOnce(tester).atlasDraws, isNotEmpty);
      await tester.pumpAndSettle();
      expect(ticks.isRunning, isTrue);
    });
  });

  group('per-sprite geometry', () {
    testWidgets('a wide frame is fitted by contain and centred in the glyph '
        'box', (tester) async {
      answerAll(size: const Size(40, 20));
      await pumpAnimated(tester, count: 1);

      final draw = paintOnce(tester).atlasDraws.single;

      const scale = _box / 40;
      expect(draw.scales.single, closeTo(scale, 1e-6));
      // Cell 0 is 80 x 40 at (0, 24): centre (40, 44).
      expect(draw.offsets.single.dx, closeTo(40 - _box / 2, 1e-4));
      expect(draw.offsets.single.dy, closeTo(44 - 20 * scale / 2, 1e-4));
    });

    testWidgets('a tall frame is limited by its height', (tester) async {
      answerAll(size: const Size(20, 40));
      await pumpAnimated(tester, count: 1);

      final draw = paintOnce(tester).atlasDraws.single;

      expect(draw.scales.single, closeTo(_box / 40, 1e-6));
    });
  });

  group('GIF cells cover their box', () {
    CatalogLeaf gif(int i) => CatalogLeaf.document(
      'gif-$i',
      semanticKind: SemanticKind.gif,
      mediaForm: MediaForm.video,
      animated: true,
    );

    Future<void> pumpGifs(WidgetTester tester, int count) async {
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [for (var i = 0; i < count; i++) gif(i)],
        ),
      ]);
      await pumpViewport(tester);
    }

    testWidgets('a wide frame is cropped left and right to the square box', (
      tester,
    ) async {
      answerAll(size: const Size(40, 20));
      await pumpGifs(tester, 1);

      final draw = paintOnce(tester).atlasDraws.single;

      // The box is the 40 px square of the 80 x 40 cell: the middle 20 x 20
      // of the frame, doubled.
      expect(draw.sources.single, const Rect.fromLTWH(10, 0, 20, 20));
      expect(draw.scales.single, closeTo(2, 1e-6));
      expect(draw.offsets.single.dx, closeTo(40 - _box / 2, 1e-4));
      expect(draw.offsets.single.dy, closeTo(44 - _box / 2, 1e-4));
    });

    testWidgets('a tall frame is cropped above and below', (tester) async {
      answerAll(size: const Size(20, 40));
      await pumpGifs(tester, 1);

      final draw = paintOnce(tester).atlasDraws.single;

      expect(draw.sources.single, const Rect.fromLTWH(0, 10, 20, 20));
      expect(draw.scales.single, closeTo(2, 1e-6));
    });

    testWidgets('a sticker in the same grid is still shown whole', (
      tester,
    ) async {
      answerAll(size: const Size(40, 20));
      snapshots.replaceSections([
        CatalogSection(id: 'a', title: 'A', leaves: [_sticker(0)]),
      ]);
      await pumpViewport(tester);

      final draw = paintOnce(tester).atlasDraws.single;

      expect(draw.sources.single, const Rect.fromLTWH(0, 0, 40, 20));
    });

    testWidgets('cropping adds no draw: still one atlas draw per page', (
      tester,
    ) async {
      answerAll(size: const Size(40, 20));
      await pumpGifs(tester, _leaves);

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws, hasLength(3));
      expect(canvas.atlasDraws.map((d) => d.sprites), everyElement(20));
      expect(canvas.imageDraws, 0);
      expect(canvas.ops.where((op) => op == 'atlas'), hasLength(3));
    });
  });

  group('fade', () {
    testWidgets('content there at attach draws at full opacity, no colours', (
      tester,
    ) async {
      answerAll();
      await pumpAnimated(tester, count: 4);

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws.first.colors, isNull);
    });

    testWidgets('content that arrives later fades in over its placeholder', (
      tester,
    ) async {
      final made = <FakeAssetPaintable>[];
      snapshots.replaceSections([
        CatalogSection(id: 'a', title: 'A', leaves: [_sticker(0)]),
      ]);
      await pumpViewport(tester);
      final attempt = producer.last;
      final paintable = attempt.advance(AssetStage.full, animated: true)
        ..spriteOnAdvance = sprite(0);
      made.add(paintable);
      await tester.pump();

      final first = paintOnce(tester);
      expect(first.atlasDraws.single.colors, isNotNull);
      expect(Color(first.atlasDraws.single.colors!.single).a, closeTo(0, 0.01));
      // The placeholder under it, so the cell is never blank mid-fade.
      expect(first.rrects, isNotEmpty);
    });
  });

  group('draw ops per frame', () {
    // 60 animated cells over 3 frame pages, the same scene with the paintable
    // before and after it exposed its sprite.
    Future<RecordingCanvas> scene(
      WidgetTester tester, {
      required bool exposesSprite,
    }) async {
      scope.dispose();
      scope = AssetCacheScope(
        producer: _FrameProducer(pages, exposesSprite: exposesSprite),
        clock: clock,
      );
      await pumpAnimated(tester);
      return paintOnce(tester);
    }

    testWidgets('without a sprite every cell is an image draw', (tester) async {
      final canvas = await scene(tester, exposesSprite: false);

      expect(canvas.imageDraws, _leaves);
      expect(canvas.atlasDraws, isEmpty);
    });

    testWidgets('with a sprite 60 cells are one atlas draw per page', (
      tester,
    ) async {
      final canvas = await scene(tester, exposesSprite: true);

      expect(canvas.atlasDraws, hasLength(pages.length));
      expect(canvas.imageDraws, 0);
      expect(
        canvas.atlasDraws.fold<int>(0, (n, draw) => n + draw.sprites),
        _leaves,
      );
    });
  });
}
