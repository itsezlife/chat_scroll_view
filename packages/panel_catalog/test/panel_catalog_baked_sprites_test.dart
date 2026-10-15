/// Baked sprites on screen: the Panel Catalog Viewport draws unicode glyphs
/// from glyph atlas pages instead of as text.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogDataSource] and a
/// [MemoryCatalogAssetCache] that carries a [GlyphAtlas] built on the fakes of
/// the bake (`FakeGlyphRasteriser`, `FakeGlyphPageStore`, `FakeBakeFrameSource`):
/// no emoji font, no device. What is observed is what the viewport asks its
/// canvas to draw (a recording canvas passed to `paint`), never render-object
/// fields: how many batched atlas draws, which page each is cut from, how many
/// sprites each holds, and that no paragraph, circle or layout comes with them.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';

const _perPage = 676; // GlyphAtlasLayout().cellsPerPage

// Geometry of the harness: 4 columns of 40 px cells under a 24 px header, in a
// 480 px viewport. At offset 0 that shows 12 rows, 48 leaves. A jump to row
// `r` is offset 24 + 40 * r.
const _span = 4;
const _visibleLeaves = 48;

// The one section header in view is text too; only glyphs are the subject.
const _headers = 1;
double _offsetOfRow(int row) => 24.0 + 40 * row;

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(int count) => CatalogSection(
  id: 'a',
  title: 'A',
  leaves: [for (var i = 0; i < count; i++) CatalogLeaf.unicode(_glyph(i))],
);

/// One batched atlas draw as the canvas received it.
class _AtlasDraw {
  _AtlasDraw(this.image, this.transforms, this.rects);

  final ui.Image image;
  final Float32List transforms;
  final Float32List rects;

  int get sprites => rects.length ~/ 4;

  /// Source rectangles, copied so a reused buffer cannot change them later.
  List<Rect> get sources => [
    for (var i = 0; i < rects.length; i += 4)
      Rect.fromLTRB(rects[i], rects[i + 1], rects[i + 2], rects[i + 3]),
  ];

  /// Scale of each sprite's transform (`scos`).
  List<double> get scales => [
    for (var i = 0; i < transforms.length; i += 4) transforms[i],
  ];
}

/// Records what one paint asks of the canvas.
class _RecordingCanvas implements Canvas {
  final List<_AtlasDraw> atlasDraws = [];
  int circles = 0;
  int paragraphs = 0;
  int highlights = 0;

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => atlasDraws.add(
    _AtlasDraw(
      atlas,
      Float32List.fromList(rstTransforms),
      Float32List.fromList(rects),
    ),
  );

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;

  @override
  void drawRRect(RRect rrect, Paint paint) => highlights++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late FakeCatalogDataSource dataSource;
  late PanelCatalogController controller;
  late FakeBakeFrameSource frames;
  late FakeGlyphPageStore store;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;
  late GlyphAtlas atlas;
  late MemoryCatalogAssetCache cache;

  setUp(() {
    PanelCatalogDiagnostics.reset();
    dataSource = FakeCatalogDataSource();
    controller = PanelCatalogController();
    frames = FakeBakeFrameSource();
    store = FakeGlyphPageStore();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() async {
    dataSource.dispose();
    controller.dispose();
    visible.dispose();
    opening.dispose();
    await store.clear();
  });

  /// An atlas over the first [count] glyphs of the harness catalogue, held by
  /// the cache the viewport is given. Not started: tests start it.
  void buildAtlas(int count) {
    atlas = GlyphAtlas(
      index: GlyphAtlasIndex([for (var i = 0; i < count; i++) _glyph(i)]),
      rasteriser: FakeGlyphRasteriser(),
      store: store,
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
    );
    cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
    addTearDown(() {
      cache.dispose();
      atlas.dispose();
    });
  }

  Future<void> pumpViewport(
    WidgetTester tester, {
    CatalogAssetCache? assetCache,
    ValueChanged<CatalogLeaf>? onLeafTap,
    void Function(CatalogLeaf leaf, LongPressStartDetails details)?
    onLeafLongPressStart,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: PanelCatalogThemeData.light,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: PanelCatalogViewport(
                dataSource: dataSource,
                assetCache: assetCache ?? cache,
                controller: controller,
                spanCount: _span,
                cellExtent: 40,
                headerExtent: 24,
                onLeafTap: onLeafTap,
                onLeafLongPressStart: onLeafLongPressStart,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  RenderBox render(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  _RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = _RecordingCanvas();
    render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  /// Frames until the bake has nothing left to ask for.
  Future<void> bakeAll(WidgetTester tester) async {
    for (var i = 0; i < 400 && frames.hasPendingRequest; i++) {
      frames.pump();
      await tester.pump();
    }
    expect(frames.hasPendingRequest, isFalse, reason: 'the bake did not end');
  }

  group('a glyph that is not baked yet', () {
    testWidgets('shows the circle placeholder, not a sprite or text', (
      tester,
    ) async {
      dataSource.replaceSections([_section(80)]);
      buildAtlas(80);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.circles, _visibleLeaves);
      expect(canvas.atlasDraws, isEmpty);
      expect(canvas.paragraphs, _headers);
    });

    testWidgets(
      'switches to its sprite when the page is ready, with no layout change',
      (tester) async {
        dataSource.replaceSections([_section(80)]);
        buildAtlas(80);
        atlas.start();
        await pumpViewport(tester);
        final sizeBefore = render(tester).size;

        // Let the bake finish without pumping the widget tree, so what the
        // page being ready asks of the viewport is still pending.
        while (frames.hasPendingRequest) {
          frames.pump();
          await tester.runAsync(pumpEventQueue);
        }

        expect(render(tester).debugNeedsPaint, isTrue);
        expect(render(tester).debugNeedsLayout, isFalse);

        await tester.pump();
        final canvas = paintOnce(tester);

        expect(canvas.circles, 0);
        expect(canvas.atlasDraws, isNotEmpty);
        expect(render(tester).size, sizeBefore);
      },
    );
  });

  group('batching', () {
    testWidgets('all sprites of one page are drawn in one batch', (
      tester,
    ) async {
      dataSource.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      await pumpViewport(tester);
      await bakeAll(tester);

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws, hasLength(1));
      expect(canvas.atlasDraws.single.sprites, _visibleLeaves);
      expect(canvas.circles, 0);
      expect(canvas.paragraphs, _headers);
    });

    testWidgets('cells cut from the right place on the page', (tester) async {
      dataSource.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      await pumpViewport(tester);
      await bakeAll(tester);

      final expected = GlyphAtlasIndex([
        for (var i = 0; i < 80; i++) _glyph(i),
      ]);
      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws.single.sources, [
        for (var i = 0; i < _visibleLeaves; i++)
          expected.placementOf(_glyph(i))!.source,
      ]);
    });

    testWidgets('a band over two pages is two batches, one per page', (
      tester,
    ) async {
      const count = _perPage + 40;
      dataSource.replaceSections([_section(count)]);
      buildAtlas(count);
      atlas.start();
      await pumpViewport(tester);
      await bakeAll(tester);

      // Half a row below row 160: rows 160..172 are in view, which is leaves
      // 640..691, 36 of them on page 0 and 16 on page 1.
      controller.jumpTo(_offsetOfRow(160) + 20);
      await tester.pump();
      final canvas = paintOnce(tester);

      final page0 = (await store.read(0))!;
      final page1 = (await store.read(1))!;
      addTearDown(page0.dispose);
      addTearDown(page1.dispose);
      expect(canvas.atlasDraws, hasLength(2));
      final byPage = {
        for (final draw in canvas.atlasDraws)
          if (draw.image.isCloneOf(page0))
            0: draw
          else if (draw.image.isCloneOf(page1))
            1: draw,
      };
      expect(byPage.keys, unorderedEquals([0, 1]));
      expect(byPage[0]!.sprites, 36);
      expect(byPage[1]!.sprites, 16);
      expect(canvas.circles, 0);
    });

    testWidgets(
      'a page that is ready draws while its neighbour shows circles',
      (tester) async {
        const count = _perPage + 40;
        dataSource.replaceSections([_section(count)]);
        buildAtlas(count);
        atlas.start();
        await pumpViewport(tester);

        // The band settles over both pages, page 0 first in view, so page 0 is
        // the first to land.
        controller.jumpTo(_offsetOfRow(160) + 20);
        await tester.pumpAndSettle();
        while (atlas.spriteOf(_glyph(640)) == null &&
            frames.hasPendingRequest) {
          frames.pump();
          await tester.pump();
        }
        expect(atlas.spriteOf(_glyph(_perPage)), isNull);

        final canvas = paintOnce(tester);

        expect(canvas.atlasDraws, hasLength(1));
        expect(canvas.atlasDraws.single.sprites, 36);
        expect(canvas.circles, 16);
      },
    );
  });

  group('text is not used to draw emoji where emoji are baked', () {
    testWidgets('scrolling the whole catalogue draws no paragraph', (
      tester,
    ) async {
      const count = 300;
      dataSource.replaceSections([_section(count)]);
      buildAtlas(count);
      atlas.start();
      await pumpViewport(tester);

      // Before the bake, during it and after it.
      for (var step = 0; step < 4; step++) {
        controller.jumpTo(step * 1500.0);
        await tester.pump();
        paintOnce(tester);
      }
      await bakeAll(tester);
      for (var step = 0; step < 4; step++) {
        controller.jumpTo(step * 1500.0);
        await tester.pump();
        paintOnce(tester);
      }

      expect(PanelCatalogDiagnostics.glyphParagraphDraws, 0);
    });
  });

  group('where nothing is baked (the web strategy)', () {
    testWidgets('glyphs are drawn as text and no bake is started', (
      tester,
    ) async {
      dataSource.replaceSections([_section(80)]);
      final plain = MemoryCatalogAssetCache();
      await pumpViewport(tester, assetCache: plain);

      PanelCatalogDiagnostics.reset();
      final canvas = paintOnce(tester);

      expect(canvas.paragraphs, _visibleLeaves + _headers);
      expect(canvas.circles, 0);
      expect(canvas.atlasDraws, isEmpty);
      expect(PanelCatalogDiagnostics.glyphParagraphDraws, _visibleLeaves);
      expect(frames.requested, 0);
    });
  });

  group('baking stays out of the way of scrolling', () {
    testWidgets('waits while a drag moves the catalogue, resumes after', (
      tester,
    ) async {
      dataSource.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      await pumpViewport(tester);
      expect(frames.hasPendingRequest, isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PanelCatalogViewport)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(controller.offset, greaterThan(0));
      expect(frames.hasPendingRequest, isFalse);

      // The finger rests: still a drag, still no bake.
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.hasPendingRequest, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(frames.hasPendingRequest, isTrue);
    });

    testWidgets('waits through a fling and a programmatic jump', (
      tester,
    ) async {
      dataSource.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      await pumpViewport(tester);

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -300),
        3000,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(frames.hasPendingRequest, isFalse);
      await tester.pumpAndSettle();
      expect(frames.hasPendingRequest, isTrue);

      controller.jumpTo(_offsetOfRow(40));
      await tester.pump();
      expect(frames.hasPendingRequest, isFalse);
      await tester.pumpAndSettle();
      expect(frames.hasPendingRequest, isTrue);
    });

    testWidgets('the band the catalogue settled on bakes first', (
      tester,
    ) async {
      // Enough below row 170 that the jump is not clamped back up.
      const count = _perPage + 200;
      dataSource.replaceSections([_section(count)]);
      buildAtlas(count);
      atlas.start();
      await pumpViewport(tester);

      // Rows 170.. are leaves 680 and up, all on page 1.
      controller.jumpTo(_offsetOfRow(170));
      await tester.pumpAndSettle();
      while (atlas.spriteOf(_glyph(_perPage)) == null &&
          frames.hasPendingRequest) {
        frames.pump();
        await tester.pump();
      }

      expect(atlas.spriteOf(_glyph(_perPage)), isNotNull);
      expect(atlas.spriteOf(_glyph(0)), isNull);
    });

    testWidgets('a viewport that goes away mid-scroll lets baking resume', (
      tester,
    ) async {
      dataSource.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      await pumpViewport(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PanelCatalogViewport)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(frames.hasPendingRequest, isFalse);

      await tester.pumpWidget(const SizedBox());
      await gesture.cancel();

      expect(frames.hasPendingRequest, isTrue);
    });
  });

  group('a host that rebuilds or swaps its cache', () {
    testWidgets('a rebuild with the same cache does not forget a drag', (
      tester,
    ) async {
      dataSource.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      await pumpViewport(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PanelCatalogViewport)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(frames.hasPendingRequest, isFalse);

      await pumpViewport(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(frames.hasPendingRequest, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a cache with another atlas takes over the reports', (
      tester,
    ) async {
      dataSource.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      final firstFrames = frames;
      await pumpViewport(tester);

      // A second atlas on its own frame source, in a second cache.
      frames = FakeBakeFrameSource();
      final firstCache = cache;
      buildAtlas(300);
      atlas.start();
      await pumpViewport(tester);
      expect(firstFrames.hasPendingRequest, isTrue);
      expect(frames.hasPendingRequest, isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PanelCatalogViewport)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();

      // Only the atlas the viewport now draws from is told to wait.
      expect(frames.hasPendingRequest, isFalse);
      expect(firstFrames.hasPendingRequest, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(identical(cache, firstCache), isFalse);
    });
  });

  group('page lifetime', () {
    testWidgets('a page that was released is not painted from', (tester) async {
      dataSource.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      await pumpViewport(tester);
      await bakeAll(tester);
      expect(paintOnce(tester).atlasDraws, isNotEmpty);

      atlas.dispose();
      controller.jumpTo(40);
      await tester.pump();
      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws, isEmpty);
      expect(canvas.circles, greaterThanOrEqualTo(_visibleLeaves));
    });
  });

  group('behaviour that must not change', () {
    testWidgets('tapping a baked cell reports that leaf', (tester) async {
      dataSource.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      final tapped = <CatalogLeaf>[];
      await pumpViewport(tester, onLeafTap: tapped.add);
      await bakeAll(tester);

      final box = tester.getRect(find.byType(PanelCatalogViewport));
      await tester.tapAt(box.topLeft + const Offset(100, 24 + 20));

      expect(tapped, hasLength(1));
      expect((tapped.single as UnicodeCatalogLeaf).glyph, _glyph(1));
    });

    testWidgets('a long press on a baked cell reports that leaf, not a tap', (
      tester,
    ) async {
      dataSource.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      final tapped = <CatalogLeaf>[];
      final pressed = <CatalogLeaf>[];
      await pumpViewport(
        tester,
        onLeafTap: tapped.add,
        onLeafLongPressStart: (leaf, _) => pressed.add(leaf),
      );
      await bakeAll(tester);

      final box = tester.getRect(find.byType(PanelCatalogViewport));
      await tester.longPressAt(box.topLeft + const Offset(100, 24 + 20));
      await tester.pumpAndSettle();

      expect(tapped, isEmpty);
      expect(pressed, hasLength(1));
      expect((pressed.single as UnicodeCatalogLeaf).glyph, _glyph(1));
    });

    testWidgets(
      'a pressed baked cell shrinks inside its batch and gets the highlight',
      (tester) async {
        dataSource.replaceSections([_section(80)]);
        buildAtlas(80);
        atlas.start();
        await pumpViewport(tester, onLeafTap: (_) {});
        await bakeAll(tester);

        final box = tester.getRect(find.byType(PanelCatalogViewport));
        final gesture = await tester.startGesture(
          box.topLeft + const Offset(20, 24 + 20),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final canvas = paintOnce(tester);
        await gesture.up();
        await tester.pumpAndSettle();

        // Same single batch; exactly one sprite is smaller than the rest.
        expect(canvas.atlasDraws, hasLength(1));
        final scales = canvas.atlasDraws.single.scales;
        final full = scales.reduce((a, b) => a > b ? a : b);
        expect(scales.where((s) => s < full), hasLength(1));
        expect(canvas.highlights, greaterThanOrEqualTo(1));
      },
    );

    testWidgets('a tap that stops a fling picks nothing', (tester) async {
      dataSource.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      final tapped = <CatalogLeaf>[];
      await pumpViewport(tester, onLeafTap: tapped.add);
      await bakeAll(tester);

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -300),
        2000,
      );
      await tester.pump(const Duration(milliseconds: 50));
      final box = tester.getRect(find.byType(PanelCatalogViewport));
      await tester.tapAt(box.center);
      await tester.pumpAndSettle();

      expect(tapped, isEmpty);
    });
  });
}
