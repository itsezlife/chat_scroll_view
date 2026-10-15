/// Scroll-time hardening of the Panel Catalog Viewport.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogDataSource] and
/// [FakeCatalogAssetCache], the same boundary as the correctness suite. Raster
/// cost is not asserted here (a headless run does no rasterisation); these tests
/// pin the structural guarantees that keep scroll-time work small:
///
/// - the viewport is its own repaint boundary (no shared layer with overlays)
/// - leaves reuse paint objects; save/restore only on the pressed leaf
/// - density comes from the view the viewport sits in
/// - the binding sync cost follows the visible band, not the catalogue size
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';

Widget _app({
  required CatalogDataSource dataSource,
  required CatalogAssetCache assetCache,
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
                    dataSource: dataSource,
                    assetCache: assetCache,
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
  late FakeCatalogDataSource dataSource;
  late FakeCatalogAssetCache assetCache;
  late PanelCatalogController controller;

  setUp(() {
    dataSource = FakeCatalogDataSource();
    assetCache = FakeCatalogAssetCache();
    controller = PanelCatalogController();
  });

  tearDown(() {
    dataSource.dispose();
    controller.dispose();
  });

  group('repaint boundary', () {
    testWidgets('the viewport paints into its own layer', (tester) async {
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 40; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);
      await tester.pumpWidget(
        _app(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );

      final render = _render(tester);
      expect(render.isRepaintBoundary, isTrue);
      expect(render.debugLayer, isA<OffsetLayer>());
    });

    testWidgets('an overlay repaint does not repaint the viewport', (
      tester,
    ) async {
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 40; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);
      final tick = ValueNotifier<int>(0);
      addTearDown(tick.dispose);
      await tester.pumpWidget(
        _app(
          dataSource: dataSource,
          assetCache: assetCache,
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
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 24; i++) CatalogLeaf.document('doc-$i'),
        ]),
      ]);
      await tester.pumpWidget(
        _app(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
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
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 24; i++) CatalogLeaf.document('doc-$i'),
        ]),
      ]);
      await tester.pumpWidget(
        _app(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
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

  group('density', () {
    testWidgets('follows the view the viewport sits in, across resizes', (
      tester,
    ) async {
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 40; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      expect(_render(tester).devicePixelRatio, 2);

      tester.view.devicePixelRatio = 3.5;
      await tester.pump();
      expect(_render(tester).devicePixelRatio, 3.5);
    });

    testWidgets('sibling subtrees keep their own density (multi-window)', (
      tester,
    ) async {
      // Two windows each carry their own MediaQuery; model that with two
      // subtrees whose density differs from the first view's.
      final secondDataSource = FakeCatalogDataSource()
        ..replaceSections([
          _section('b', [
            for (var i = 0; i < 40; i++)
              CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
          ]),
        ]);
      addTearDown(secondDataSource.dispose);
      final secondController = PanelCatalogController();
      addTearDown(secondController.dispose);
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 40; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);

      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget host(CatalogDataSource ds, PanelCatalogController c, double dpr) =>
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(devicePixelRatio: dpr),
              child: SizedBox(
                width: 160,
                height: 200,
                child: PanelCatalogViewport(
                  dataSource: ds,
                  assetCache: assetCache,
                  controller: c,
                ),
              ),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: PanelCatalogTheme(
            data: PanelCatalogThemeData.light,
            child: Row(
              children: [
                host(dataSource, controller, 2),
                host(secondDataSource, secondController, 3),
              ],
            ),
          ),
        ),
      );

      final renders = tester
          .renderObjectList<RenderPanelCatalog>(
            find.byType(PanelCatalogViewport),
          )
          .toList();
      expect(renders.map((r) => r.devicePixelRatio), [2.0, 3.0]);
    });
  });

  group('visible-band lookup', () {
    testWidgets('scroll cost does not grow with catalogue size', (
      tester,
    ) async {
      Future<double> scrollCostFor(int leafCount) async {
        final ds = FakeCatalogDataSource()
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
          _app(dataSource: ds, assetCache: assetCache, controller: c),
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
