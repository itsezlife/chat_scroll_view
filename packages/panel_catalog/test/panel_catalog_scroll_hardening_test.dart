/// Scroll-time hardening of the Panel Catalog Viewport.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource] and
/// a `TextGlyphProducer` scope, the same boundary as the correctness suite. Raster
/// cost is not asserted here (a headless run does no rasterisation); these tests
/// pin the structural guarantees that keep scroll-time work small:
///
/// - the viewport is its own repaint boundary (no shared layer with overlays)
/// - leaves reuse paint objects; save/restore only on the pressed leaf
/// - density comes from the view the viewport sits in
/// - the binding sync cost follows the visible band, not the catalogue size
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

Widget _app({
  required ValueObservable<CatalogSnapshot> snapshots,
  required AssetCacheScope assets,
  required PanelCatalogController controller,
  List<Widget> overlays = const [],
  double width = 320,
  double height = 480,
  int spanCount = 4,
  double cellExtent = 40,
  double headerExtent = 24,
}) {
  return MaterialApp(
    home: PanelCatalogTheme(
      data: PanelCatalogThemeData.light,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PanelCatalogViewport(
                    snapshots: snapshots,
                    assets: assets,
                    controller: controller,
                    spanCount: spanCount,
                    cellExtent: cellExtent,
                    headerExtent: headerExtent,
                  ),
                ),
                ...overlays,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

CatalogSection _section(String id, List<CatalogLeaf> leaves) =>
    CatalogSection(id: id, title: 'Section $id', leaves: leaves);

RenderPanelCatalog _render(WidgetTester tester) =>
    tester.renderObject(find.byType(PanelCatalogViewport));

/// Canvas that records the identity of the [Paint] behind every fill so a test
/// can tell reuse from per-leaf allocation, and counts `save` calls.
class _SpyCanvas implements Canvas {
  final List<Paint> rrectPaints = [];
  final List<Paint> circlePaints = [];
  int saves = 0;

  @override
  void drawRRect(RRect rrect, Paint paint) => rrectPaints.add(paint);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circlePaints.add(paint);

  @override
  void save() => saves++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

_SpyCanvas _paintOnce(RenderPanelCatalog render) {
  final canvas = _SpyCanvas();
  render.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return canvas;
}

/// Median wall time of [runs] calls to [body], in microseconds.
double _medianMicros(int runs, void Function() body) {
  final samples = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < runs; i++) {
    sw
      ..reset()
      ..start();
    body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2].toDouble();
}

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late AssetCacheScope assetScope;
  late PanelCatalogController controller;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    assetScope = textGlyphScope();
    controller = PanelCatalogController();
  });

  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  group('repaint boundary', () {
    testWidgets('the viewport paints into its own layer', (tester) async {
      snapshots.replaceSections([
        _section('a', [
          for (var i = 0; i < 40; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);
      await tester.pumpWidget(
        _app(snapshots: snapshots, assets: assetScope, controller: controller),
      );

      final render = _render(tester);
      expect(render.isRepaintBoundary, isTrue);
      expect(render.debugLayer, isA<OffsetLayer>());
    });

    testWidgets('an overlay repaint does not repaint the viewport', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('a', [
          for (var i = 0; i < 40; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);
      final tick = ValueNotifier<int>(0);
      addTearDown(tick.dispose);
      await tester.pumpWidget(
        _app(
          snapshots: snapshots,
          assets: assetScope,
          controller: controller,
          overlays: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 24,
              child: CustomPaint(painter: _TickPainter(tick)),
            ),
          ],
        ),
      );

      final render = _render(tester);
      // Sentinel: every viewport paint overwrites this with a real duration.
      const sentinel = Duration(days: 1);
      render.debugLastPaintDuration = sentinel;

      tick.value++;
      await tester.pump();
      expect(
        render.debugLastPaintDuration,
        sentinel,
        reason: 'overlay repaint must reuse the viewport layer',
      );

      controller.scrollBy(10);
      await tester.pump();
      expect(render.debugLastPaintDuration, isNot(sentinel));
    });
  });

  group('per-leaf paint objects', () {
    testWidgets('placeholder fills share one paint across leaves', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('a', [
          for (var i = 0; i < 24; i++) CatalogLeaf.document('doc-$i'),
        ]),
      ]);
      await tester.pumpWidget(
        _app(snapshots: snapshots, assets: assetScope, controller: controller),
      );

      final canvas = _paintOnce(_render(tester));

      expect(canvas.rrectPaints.length, greaterThan(8));
      expect(
        canvas.rrectPaints.toSet(),
        hasLength(1),
        reason: 'one hoisted paint, not one per leaf',
      );
    });

    testWidgets('save is spent only on the pressed leaf', (tester) async {
      snapshots.replaceSections([
        _section('a', [
          for (var i = 0; i < 24; i++) CatalogLeaf.document('doc-$i'),
        ]),
      ]);
      await tester.pumpWidget(
        _app(snapshots: snapshots, assets: assetScope, controller: controller),
      );
      final render = _render(tester);
      final idleSaves = _paintOnce(render).saves;

      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(PanelCatalogViewport)) +
            const Offset(20, 44),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(render.pressedSlotKey, isNotNull);
      final pressedSaves = _paintOnce(render).saves;
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pressedSaves - idleSaves, 1);
    });
  });

  group('visible-band lookup', () {
    testWidgets('scroll cost does not grow with catalogue size', (
      tester,
    ) async {
      Future<double> scrollCostFor(int leafCount) async {
        final ds = FakeCatalogSnapshotSource()
          ..replaceSections([
            _section('a', [
              for (var i = 0; i < leafCount; i++)
                CatalogLeaf.unicode(
                  '${String.fromCharCode(0x20000 + i % 0x10000)}$i',
                ),
            ]),
          ]);
        addTearDown(ds.dispose);
        final c = PanelCatalogController();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          _app(snapshots: ds, assets: assetScope, controller: c),
        );
        // Park deep in the catalogue so a front-to-back scan has to walk it.
        c.jumpTo(_render(tester).maxOffset / 2);
        await tester.pump();
        return _medianMicros(300, () => c.scrollBy(1));
      }

      final small = await scrollCostFor(400);
      final large = await scrollCostFor(400000);

      // O(visible band): both are a handful of microseconds. A linear walk over
      // 400k slots costs milliseconds, three orders of magnitude above this.
      expect(large, lessThan(small * 8 + 250));
    });

    testWidgets('stays proportional to the band with per-section layouts', (
      tester,
    ) async {
      // Alternating default and 5-column sections: 160 sections of 100 leaves
      // against 320000 of them.
      Future<({double scroll, double hit})> costsFor(int sectionCount) async {
        final ds = FakeCatalogSnapshotSource()
          ..replaceSections([
            for (var s = 0; s < sectionCount; s++)
              CatalogSection(
                id: 's$s',
                title: 'Section $s',
                layout: s.isOdd
                    ? const SectionLayout.grid(spanCount: 5, cellExtent: 64)
                    : null,
                leaves: [
                  for (var i = 0; i < 100; i++)
                    CatalogLeaf.unicode(
                      '${String.fromCharCode(0x20000 + i % 0x10000)}$s',
                    ),
                ],
              ),
          ]);
        addTearDown(ds.dispose);
        final c = PanelCatalogController();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          _app(snapshots: ds, assets: assetScope, controller: c),
        );
        final render = _render(tester);
        c.jumpTo(render.maxOffset / 2);
        await tester.pump();
        return (
          scroll: _medianMicros(300, () => c.scrollBy(1)),
          hit: _medianMicros(
            300,
            () => render.leafSlotAt(const Offset(100, 200)),
          ),
        );
      }

      final small = await costsFor(2);
      final large = await costsFor(3200);

      // Binary search over the one ascending slot list, then the visible band:
      // a front-to-back scan of 320000 slots costs milliseconds.
      expect(large.scroll, lessThan(small.scroll * 8 + 250));
      expect(large.hit, lessThan(small.hit * 8 + 120));
    });
  });
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.tick) : super(repaint: tick);

  final ValueNotifier<int> tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x11000000),
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => false;
}
