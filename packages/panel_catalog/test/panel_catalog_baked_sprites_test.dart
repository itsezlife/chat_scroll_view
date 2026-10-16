/// Baked sprites on screen: the Panel Catalog Viewport draws unicode glyphs
/// from glyph atlas pages instead of as text.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource] and
/// an [AssetCacheScope] whose glyph source is a [GlyphAtlas] built on the fakes
/// of the bake (`FakeGlyphRasteriser`, `FakeGlyphPageStore`,
/// `FakeBakeFrameSource`): no emoji font, no device. What is observed is what
/// the viewport asks its canvas to draw (a recording canvas passed to `paint`),
/// never render-object fields: how many batched atlas draws, which page each is
/// cut from, how many sprites each holds, and that no paragraph, circle or
/// layout comes with them.
///
/// The viewport names no atlas. The page that owns the bake listens to the
/// controller's events and tells the atlas; `_PageBake` below is that listener,
/// so the chain from a drag to a paused bake is still pinned end to end.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';
import 'support/recording_canvas.dart';

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

/// What the page that owns the bake does with the controller's events: tells
/// the atlas when the catalogue moves and which glyphs it settled on.
class _PageBake {
  _PageBake(this.atlas, this.events) {
    events.addListener(_onEvent);
  }

  final GlyphAtlas atlas;
  final EventObservable<PanelCatalogScrollEvent> events;

  void dispose() => events.removeListener(_onEvent);

  void _onEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogScrollingChanged(:final scrolling):
        atlas.reportScrolling(reporter: this, scrolling: scrolling);
      case PanelCatalogScrollSettled(:final visibleKeys):
        atlas.prioritise([
          for (final key in visibleKeys)
            if (key is ContentKey$Unicode) key.sequence,
        ]);
      default:
        break;
    }
  }
}

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeBakeFrameSource frames;
  late FakeGlyphPageStore store;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;
  late GlyphAtlas atlas;
  late AssetCacheScope scope;
  _PageBake? pageBake;

  setUp(() {
    PanelCatalogDiagnostics.reset();
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    frames = FakeBakeFrameSource();
    store = FakeGlyphPageStore();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() async {
    pageBake?.dispose();
    pageBake = null;
    snapshots.dispose();
    controller.dispose();
    visible.dispose();
    opening.dispose();
    await store.clear();
  });

  /// An atlas over the first [count] glyphs of the harness catalogue, the glyph
  /// source of the scope the viewport is given, and the page that forwards the
  /// viewport's events to it. Not started: tests start it.
  void buildAtlas(int count, {GlyphAtlasLayout? layout}) {
    atlas = GlyphAtlas(
      index: GlyphAtlasIndex([
        for (var i = 0; i < count; i++) _glyph(i),
      ], layout: layout ?? const GlyphAtlasLayout()),
      rasteriser: FakeGlyphRasteriser(),
      store: store,
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
    );
    scope = AssetCacheScope(glyphSource: atlas);
    pageBake?.dispose();
    pageBake = _PageBake(atlas, controller.events);
    addTearDown(() {
      scope.dispose();
      atlas.dispose();
    });
  }

  Future<void> pumpViewport(
    WidgetTester tester, {
    AssetCacheScope? assets,
    double width = 320,
    ValueChanged<CatalogLeafHit>? onLeafTap,
    void Function(CatalogLeafHit hit, LongPressStartDetails details)?
    onLeafLongPressStart,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: PanelCatalogThemeData.light,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 480,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: assets ?? scope,
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

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
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
      snapshots.replaceSections([_section(80)]);
      buildAtlas(80);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.circles.length, _visibleLeaves);
      expect(canvas.atlasDraws, isEmpty);
      expect(canvas.paragraphs, _headers);
    });

    testWidgets(
      'switches to its sprite when the page is ready, with no layout change',
      (tester) async {
        snapshots.replaceSections([_section(80)]);
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

        expect(canvas.circles.length, 0);
        expect(canvas.atlasDraws, isNotEmpty);
        expect(render(tester).size, sizeBefore);
      },
    );
  });

  group('batching', () {
    testWidgets('all sprites of one page are drawn in one batch', (
      tester,
    ) async {
      snapshots.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      await pumpViewport(tester);
      await bakeAll(tester);

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws, hasLength(1));
      expect(canvas.atlasDraws.single.sprites, _visibleLeaves);
      expect(canvas.circles.length, 0);
      expect(canvas.paragraphs, _headers);
    });

    testWidgets('cells cut from the right place on the page', (tester) async {
      snapshots.replaceSections([_section(80)]);
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
      snapshots.replaceSections([_section(count)]);
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
      expect(canvas.circles.length, 0);
    });

    testWidgets(
      'a page that is ready draws while its neighbour shows circles',
      (tester) async {
        const count = _perPage + 40;
        snapshots.replaceSections([_section(count)]);
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
        expect(canvas.circles.length, 16);
      },
    );
  });

  group('sections with different cell sizes share one atlas', () {
    testWidgets('a single baked size, scaled down, never up', (tester) async {
      // 4 columns of 40 (a 28.8 glyph box) and 2 columns of 160 x 80 (57.6).
      final sections = [
        CatalogSection(
          id: 'small',
          title: 'Small',
          leaves: [for (var i = 0; i < 8; i++) CatalogLeaf.unicode(_glyph(i))],
        ),
        CatalogSection(
          id: 'large',
          title: 'Large',
          layout: const SectionLayout.grid(spanCount: 2, cellExtent: 80),
          leaves: [for (var i = 8; i < 16; i++) CatalogLeaf.unicode(_glyph(i))],
        ),
      ];
      snapshots.replaceSections(sections);
      final largest = largestCatalogGlyphBox(
        layouts: [for (final section in sections) section.layout],
        spanCount: _span,
        cellExtent: 40,
        padding: EdgeInsets.zero,
        maxWidth: 320,
      );
      expect(largest, 80 * kCatalogGlyphBoxFraction);
      final layout = GlyphAtlasLayout.forCell(
        logicalExtent: largest,
        devicePixelRatio: 1,
      );
      expect(layout.glyphSize, 58);
      buildAtlas(16, layout: layout);
      atlas.start();
      await pumpViewport(tester);
      await bakeAll(tester);

      final canvas = paintOnce(tester);

      // One page, one draw: the large cells are not served by a second atlas.
      expect(canvas.atlasDraws, hasLength(1));
      final scales = canvas.atlasDraws.single.scales;
      expect(scales, hasLength(16));
      expect(scales.take(8), everyElement(closeTo(28.8 / 58, 1e-6)));
      expect(scales.skip(8), everyElement(closeTo(57.6 / 58, 1e-6)));
      expect(scales, everyElement(lessThanOrEqualTo(1)));
      expect(canvas.circles.length, 0);
    });
  });

  group('text is not used to draw emoji where emoji are baked', () {
    testWidgets('scrolling the whole catalogue draws no paragraph', (
      tester,
    ) async {
      const count = 300;
      snapshots.replaceSections([_section(count)]);
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

  group('no emoji paragraph is requested where emoji are baked', () {
    testWidgets(
      'not through resizes, a press, a released atlas or an unbaked page',
      (tester) async {
        const count = 300;
        snapshots.replaceSections([_section(count)]);
        buildAtlas(count);
        atlas.start();
        await pumpViewport(tester);

        for (var i = 0; i < 40; i++) {
          await pumpViewport(tester, width: 60 + i * 2.5);
          expect(paintOnce(tester).paragraphs, lessThanOrEqualTo(_headers));
        }
        await bakeAll(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PanelCatalogViewport)),
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(paintOnce(tester).paragraphs, lessThanOrEqualTo(_headers));
        await gesture.up();
        await tester.pumpAndSettle();
        atlas.dispose();
        controller.jumpTo(40);
        await tester.pump();
        expect(paintOnce(tester).paragraphs, lessThanOrEqualTo(_headers));

        expect(PanelCatalogDiagnostics.glyphParagraphDraws, 0);
      },
    );
  });

  group('where nothing is baked (the web strategy)', () {
    testWidgets('glyphs are drawn as text and no bake is started', (
      tester,
    ) async {
      snapshots.replaceSections([_section(80)]);
      final plain = textGlyphScope();
      await pumpViewport(tester, assets: plain);

      PanelCatalogDiagnostics.reset();
      final canvas = paintOnce(tester);

      expect(canvas.paragraphs, _visibleLeaves + _headers);
      expect(canvas.circles.length, 0);
      expect(canvas.atlasDraws, isEmpty);
      expect(PanelCatalogDiagnostics.glyphParagraphDraws, _visibleLeaves);
      expect(frames.requested, 0);
    });
  });

  group('baking stays out of the way of scrolling', () {
    testWidgets('waits while a drag moves the catalogue, resumes after', (
      tester,
    ) async {
      snapshots.replaceSections([_section(300)]);
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
      snapshots.replaceSections([_section(300)]);
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
      snapshots.replaceSections([_section(count)]);
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
      snapshots.replaceSections([_section(300)]);
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
      snapshots.replaceSections([_section(300)]);
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

    testWidgets('a scope with another atlas takes over the bindings', (
      tester,
    ) async {
      // A hidden panel holds no page of its own, so the counts below are the
      // bindings' alone.
      visible.value = false;
      snapshots.replaceSections([_section(300)]);
      buildAtlas(300);
      final firstAtlas = atlas;
      await pumpViewport(tester);
      expect(firstAtlas.residency.holdCount(0), greaterThan(0));

      frames = FakeBakeFrameSource();
      buildAtlas(300);
      await pumpViewport(tester);

      // The viewport draws from the new scope: circles, and the first atlas has
      // no page held for it any more.
      expect(firstAtlas.residency.holdCount(0), 0);
      expect(atlas.residency.holdCount(0), greaterThan(0));
      final canvas = paintOnce(tester);
      expect(canvas.atlasDraws, isEmpty);
      expect(canvas.circles.length, _visibleLeaves);
    });
  });

  group('page holds', () {
    // A source of fixed pages whose hold counts a test reads, in place of an
    // atlas: 100 glyphs to a page, so rows 0..12 sit on page 0.
    late FakeGlyphSpriteSource source;

    Future<void> pumpOn(WidgetTester tester) async {
      source = FakeGlyphSpriteSource([
        for (var i = 0; i < 400; i++) _glyph(i),
      ], glyphsPerPage: 100);
      final onSource = AssetCacheScope(glyphSource: source);
      addTearDown(() {
        onSource.dispose();
        source.dispose();
      });
      snapshots.replaceSections([_section(400)]);
      await pumpViewport(tester, assets: onSource);
    }

    testWidgets('a visible glyph holds its page, never its pixels', (
      tester,
    ) async {
      await pumpOn(tester);

      // Every attached glyph (the window plus one row of overscan) holds once.
      expect(
        source.holdCount(0),
        (render(tester) as RenderPanelCatalog).attachedLeafCount,
      );
      expect(source.holdCount(1), 0);

      // The page going away under memory pressure leaves the count alone, and
      // nothing is drawn from it.
      source.bakePage(0);
      await tester.pump();
      expect(paintOnce(tester).atlasDraws, hasLength(1));
      final held = source.holdCount(0);
      source.releasePage(0);
      await tester.pump();
      expect(source.holdCount(0), held);
      expect(paintOnce(tester).atlasDraws, isEmpty);
    });

    testWidgets('far bindings release their page', (tester) async {
      await pumpOn(tester);
      expect(source.holdCount(0), greaterThan(0));

      // Row 60 is leaf 240, on page 2.
      controller.jumpTo(_offsetOfRow(60));
      await tester.pump();

      expect(source.holdCount(0), 0);
      expect(source.holdCount(2), greaterThan(0));
      expect(
        source.holdCount(1) + source.holdCount(2) + source.holdCount(3),
        (render(tester) as RenderPanelCatalog).attachedLeafCount,
      );
    });

    testWidgets('leaving the tree gives every page back', (tester) async {
      await pumpOn(tester);
      expect(source.holdCount(0), greaterThan(0));

      await tester.pumpWidget(const SizedBox());

      expect(source.holdCount(0), 0);
    });
  });

  group('page lifetime', () {
    testWidgets('a page that was released is not painted from', (tester) async {
      snapshots.replaceSections([_section(80)]);
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
      expect(canvas.circles.length, greaterThanOrEqualTo(_visibleLeaves));
    });
  });

  group('behaviour that must not change', () {
    testWidgets('tapping a baked cell reports that leaf', (tester) async {
      snapshots.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      final tapped = <CatalogLeafHit>[];
      await pumpViewport(tester, onLeafTap: tapped.add);
      await bakeAll(tester);

      final box = tester.getRect(find.byType(PanelCatalogViewport));
      await tester.tapAt(box.topLeft + const Offset(100, 24 + 20));

      expect(tapped, hasLength(1));
      expect(tapped.single.leaf, CatalogLeaf.unicode(_glyph(1)));
      expect(tapped.single.index, 1);
    });

    testWidgets('a long press on a baked cell reports that leaf, not a tap', (
      tester,
    ) async {
      snapshots.replaceSections([_section(80)]);
      buildAtlas(80);
      atlas.start();
      final tapped = <CatalogLeafHit>[];
      final pressed = <CatalogLeafHit>[];
      await pumpViewport(
        tester,
        onLeafTap: tapped.add,
        onLeafLongPressStart: (hit, _) => pressed.add(hit),
      );
      await bakeAll(tester);

      final box = tester.getRect(find.byType(PanelCatalogViewport));
      await tester.longPressAt(box.topLeft + const Offset(100, 24 + 20));
      await tester.pumpAndSettle();

      expect(tapped, isEmpty);
      expect(pressed, hasLength(1));
      expect(pressed.single.leaf, CatalogLeaf.unicode(_glyph(1)));
    });

    testWidgets(
      'a pressed baked cell shrinks inside its batch and gets the highlight',
      (tester) async {
        snapshots.replaceSections([_section(80)]);
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
        expect(canvas.rrects.length, greaterThanOrEqualTo(1));
      },
    );

    testWidgets('a tap that stops a fling picks nothing', (tester) async {
      snapshots.replaceSections([_section(300)]);
      buildAtlas(300);
      atlas.start();
      final tapped = <CatalogLeafHit>[];
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
