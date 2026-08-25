// Headless A/B/C benchmark: Panel Catalog Viewport vs
// (1) frozen SuperSliverList + widget cells, and
// (2) idiomatic sectioned SliverGrid (what most packages use).
//
//   flutter test test/benchmark/vs_supersliver_bench_test.dart
//
// Debug mode — absolute µs inflated by asserts; ratios are the signal.
// Report: test/benchmark/benchmark_report.md

import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_far_stitch.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';

import 'shared/baseline_sliver_grid_catalog.dart';
import 'shared/baseline_supersliver_catalog.dart';
import 'shared/catalog_presets.dart';
import 'shared/metrics.dart';

enum _BaselineKind { superSliver, sliverGrid }

// ---------------------------------------------------------------------------
// Harnesses
// ---------------------------------------------------------------------------

Widget _candidateApp({
  required CatalogDataSource dataSource,
  required CatalogAssetCache assetCache,
  required PanelCatalogController controller,
  double width = 400,
  double height = 600,
}) {
  return MaterialApp(
    home: PanelCatalogTheme(
      data: PanelCatalogThemeData.light,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: PanelCatalogViewport(
              dataSource: dataSource,
              assetCache: assetCache,
              controller: controller,
              spanCount: kBenchSpanCount,
              cellExtent: kBenchCellExtent,
              headerExtent: kBenchHeaderExtent,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _baselineApp({
  required _BaselineKind kind,
  required List<CatalogSection> sections,
  required ScrollController scrollController,
  Key? catalogKey,
  double width = 400,
  double height = 600,
}) {
  final body = switch (kind) {
    _BaselineKind.superSliver => BaselineSuperSliverCatalog(
      key: catalogKey,
      sections: sections,
      scrollController: scrollController,
      spanCount: kBenchSpanCount,
    ),
    _BaselineKind.sliverGrid => BaselineSliverGridCatalog(
      key: catalogKey,
      sections: sections,
      scrollController: scrollController,
      spanCount: kBenchSpanCount,
    ),
  };
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: body),
      ),
    ),
  );
}

RenderPanelCatalog _candidateRender(WidgetTester tester) =>
    tester.renderObject(find.byType(PanelCatalogViewport));

RenderBenchmarkTimingWrapper _timingRender(WidgetTester tester) =>
    tester.renderObject(find.byType(BenchmarkTimingWrapper));

int _renderObjectCount(WidgetTester tester) {
  var n = 0;
  void visit(Element e) {
    if (e.renderObject != null) n++;
    e.visitChildren(visit);
  }

  visit(tester.element(find.byType(MaterialApp)));
  return n;
}

int _glyphCellCount(WidgetTester tester) => tester
    .elementList(find.byType(BaselineGlyphCell, skipOffstage: false))
    .length;

Future<List<int>> _flingFrameSamples(WidgetTester tester, Finder target) async {
  final samples = <int>[];
  await tester.fling(target, const Offset(0, -500), 2000);
  for (var i = 0; i < 300; i++) {
    final sw = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 16));
    samples.add(sw.elapsedMicroseconds);
  }
  return samples;
}

Future<List<int>> _pumpUntilSettledSamples(
  WidgetTester tester, {
  required Future<void> Function() start,
  int maxFrames = 120,
}) async {
  final samples = <int>[];
  final future = start();
  for (var i = 0; i < maxFrames; i++) {
    final sw = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 16));
    samples.add(sw.elapsedMicroseconds);
  }
  // Bound drain — Grid far animateTo can keep scheduling frames; default
  // pumpAndSettle timeout is 10 minutes and looks like a hang.
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
  } on FlutterError {
    // Timed out still settling; sampled frames remain valid.
  }
  try {
    await future.timeout(const Duration(seconds: 1));
  } on TimeoutException {
    // Samples cover maxFrames; ignore leftover animation future.
  }
  return samples;
}

String _label(_BaselineKind kind) => switch (kind) {
  _BaselineKind.superSliver => 'SSL',
  _BaselineKind.sliverGrid => 'Grid',
};

double _baselineHeaderOffset({
  required _BaselineKind kind,
  required int sectionIndex,
  required GlobalKey<BaselineSuperSliverCatalogState> sslKey,
  required GlobalKey<BaselineSliverGridCatalogState> gridKey,
}) {
  return switch (kind) {
    _BaselineKind.superSliver => sslKey.currentState!.headerOffset(
      sectionIndex,
    ),
    _BaselineKind.sliverGrid => gridKey.currentState!.headerOffset(
      sectionIndex,
    ),
  };
}

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

void main() {
  final layoutSsl = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final layoutGrid = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final paintSsl = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final paintGrid = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final flingSsl = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final flingGrid = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final nearSsl = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final nearGrid = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final farSsl = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final farGrid = <(int, BenchmarkMetrics, BenchmarkMetrics)>[];
  final memRestSsl = <(int, CatalogMemorySnapshot, CatalogMemorySnapshot)>[];
  final memRestGrid = <(int, CatalogMemorySnapshot, CatalogMemorySnapshot)>[];
  final memScrollSsl = <(int, CatalogMemorySnapshot, CatalogMemorySnapshot)>[];
  final memScrollGrid = <(int, CatalogMemorySnapshot, CatalogMemorySnapshot)>[];

  for (final leafCount in kBenchLeafCounts) {
    testWidgets('forced layout — $leafCount leaves', (tester) async {
      final sections = generateCatalogSections(leafCount);

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();

      Future<void> pumpCand(double width) async {
        await tester.pumpWidget(
          _candidateApp(
            dataSource: dataSource,
            assetCache: assetCache,
            controller: controller,
            width: width,
          ),
        );
      }

      await pumpCand(400);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await pumpCand(400 + (i.isEven ? 0 : 1));
        await tester.pump();
      }
      final candLayout = <int>[];
      for (var i = 0; i < 100; i++) {
        await pumpCand(400 + (i.isEven ? 0 : 1));
        await tester.pump();
        candLayout.add(
          _candidateRender(tester).debugLastLayoutDuration.inMicroseconds,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();
      final cand = BenchmarkMetrics('PCV layout', candLayout);

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        Future<void> pumpBase(double width) async {
          await tester.pumpWidget(
            _baselineApp(
              kind: kind,
              sections: sections,
              scrollController: sc,
              width: width,
            ),
          );
        }

        await pumpBase(400);
        await tester.pumpAndSettle();
        for (var i = 0; i < 10; i++) {
          await pumpBase(400 + (i.isEven ? 0 : 1));
          await tester.pump();
        }
        final baseLayout = <int>[];
        for (var i = 0; i < 100; i++) {
          await pumpBase(400 + (i.isEven ? 0 : 1));
          await tester.pump();
          baseLayout.add(
            _timingRender(tester).debugLastLayoutDuration.inMicroseconds,
          );
        }
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        final base = BenchmarkMetrics('${_label(kind)} layout', baseLayout);
        switch (kind) {
          case _BaselineKind.superSliver:
            layoutSsl.add((leafCount, cand, base));
          case _BaselineKind.sliverGrid:
            layoutGrid.add((leafCount, cand, base));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — layout vs ${_label(kind)}:\n  $cand\n  $base',
        );
      }
    });

    testWidgets('scroll-only paint — $leafCount leaves', (tester) async {
      final sections = generateCatalogSections(leafCount);

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();
      await tester.pumpWidget(
        _candidateApp(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final candRo = _candidateRender(tester);
      for (var i = 0; i < 10; i++) {
        controller.scrollBy(5);
        await tester.pump();
      }
      final candPaint = <int>[];
      for (var i = 0; i < 300; i++) {
        controller.scrollBy(3);
        await tester.pump();
        candPaint.add(candRo.debugLastPaintDuration.inMicroseconds);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();
      final cand = BenchmarkMetrics('PCV paint', candPaint);

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        await tester.pumpWidget(
          _baselineApp(kind: kind, sections: sections, scrollController: sc),
        );
        await tester.pumpAndSettle();
        final baseRo = _timingRender(tester);
        for (var i = 0; i < 10; i++) {
          sc.jumpTo((sc.offset + 5).clamp(0.0, sc.position.maxScrollExtent));
          baseRo.markNeedsPaint();
          await tester.pump();
        }
        final basePaint = <int>[];
        for (var i = 0; i < 300; i++) {
          sc.jumpTo((sc.offset + 3).clamp(0.0, sc.position.maxScrollExtent));
          baseRo.markNeedsPaint();
          await tester.pump();
          basePaint.add(baseRo.debugLastPaintDuration.inMicroseconds);
        }
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        final base = BenchmarkMetrics('${_label(kind)} paint', basePaint);
        switch (kind) {
          case _BaselineKind.superSliver:
            paintSsl.add((leafCount, cand, base));
          case _BaselineKind.sliverGrid:
            paintGrid.add((leafCount, cand, base));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — paint vs ${_label(kind)}:\n  $cand\n  $base',
        );
      }
    });

    testWidgets('fling frame timing — $leafCount leaves', (tester) async {
      final sections = generateCatalogSections(leafCount);

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();
      await tester.pumpWidget(
        _candidateApp(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(_candidateRender(tester).maxOffset / 2);
      await tester.pumpAndSettle();
      final candFling = await _flingFrameSamples(
        tester,
        find.byType(PanelCatalogViewport),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();
      final cand = BenchmarkMetrics('PCV fling', candFling);

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        await tester.pumpWidget(
          _baselineApp(kind: kind, sections: sections, scrollController: sc),
        );
        await tester.pumpAndSettle();
        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();
        final baseFling = await _flingFrameSamples(
          tester,
          find.byType(CustomScrollView),
        );
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        final base = BenchmarkMetrics('${_label(kind)} fling', baseFling);
        switch (kind) {
          case _BaselineKind.superSliver:
            flingSsl.add((leafCount, cand, base));
          case _BaselineKind.sliverGrid:
            flingGrid.add((leafCount, cand, base));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — fling vs ${_label(kind)}:\n  $cand\n  $base',
        );
      }
    });

    testWidgets('near-path section jump — $leafCount leaves', (tester) async {
      final sections = generateCatalogSections(leafCount);
      if (sections.length < 2) {
        // ignore: avoid_print
        print('skip near-path: need ≥2 sections');
        return;
      }

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();
      await tester.pumpWidget(
        _candidateApp(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final candNear = await _pumpUntilSettledSamples(
        tester,
        start: () => controller.jumpToSection(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();
      final cand = BenchmarkMetrics('PCV near', candNear);

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        final sslKey = GlobalKey<BaselineSuperSliverCatalogState>();
        final gridKey = GlobalKey<BaselineSliverGridCatalogState>();
        await tester.pumpWidget(
          _baselineApp(
            kind: kind,
            sections: sections,
            scrollController: sc,
            catalogKey: switch (kind) {
              _BaselineKind.superSliver => sslKey,
              _BaselineKind.sliverGrid => gridKey,
            },
          ),
        );
        await tester.pumpAndSettle();
        final target = _baselineHeaderOffset(
          kind: kind,
          sectionIndex: 1,
          sslKey: sslKey,
          gridKey: gridKey,
        );
        final baseNear = await _pumpUntilSettledSamples(
          tester,
          start: () => sc.animateTo(
            target.clamp(0.0, sc.position.maxScrollExtent),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        final base = BenchmarkMetrics('${_label(kind)} near', baseNear);
        switch (kind) {
          case _BaselineKind.superSliver:
            nearSsl.add((leafCount, cand, base));
          case _BaselineKind.sliverGrid:
            nearGrid.add((leafCount, cand, base));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — near vs ${_label(kind)}:\n  $cand\n  $base',
        );
      }
    });

    testWidgets('far-path stitch vs animateTo — $leafCount leaves', (
      tester,
    ) async {
      final sections = generateCatalogSections(leafCount);
      if (sections.length < 6) {
        // ignore: avoid_print
        print('skip far-path: need ≥6 sections');
        return;
      }

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();
      await tester.pumpWidget(
        _candidateApp(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final farSection = sections.length - 1;
      final candFar = await _pumpUntilSettledSamples(
        tester,
        start: () => controller.jumpToSection(farSection),
        maxFrames: 180,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();
      final cand = BenchmarkMetrics('PCV far stitch', candFar);

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        final sslKey = GlobalKey<BaselineSuperSliverCatalogState>();
        final gridKey = GlobalKey<BaselineSliverGridCatalogState>();
        await tester.pumpWidget(
          _baselineApp(
            kind: kind,
            sections: sections,
            scrollController: sc,
            catalogKey: switch (kind) {
              _BaselineKind.superSliver => sslKey,
              _BaselineKind.sliverGrid => gridKey,
            },
          ),
        );
        await tester.pumpAndSettle();
        final target = _baselineHeaderOffset(
          kind: kind,
          sectionIndex: farSection,
          sslKey: sslKey,
          gridKey: gridKey,
        );
        final to = target.clamp(0.0, sc.position.maxScrollExtent);
        final travel = (to - sc.offset).abs();
        // Same travel-scaled window as stitch — honest “smooth scroll the gap”
        // alternative that stitch replaces.
        final duration = catalogStitchTravelDuration(
          travelPx: travel,
          viewportHeight: kBenchViewportSize.height,
        );
        final maxFrames = (duration.inMilliseconds / 16).ceil().clamp(60, 180);
        final baseFar = await _pumpUntilSettledSamples(
          tester,
          start: () =>
              sc.animateTo(to, duration: duration, curve: Curves.easeOutCubic),
          maxFrames: maxFrames,
        );
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        final base = BenchmarkMetrics('${_label(kind)} far animateTo', baseFar);
        switch (kind) {
          case _BaselineKind.superSliver:
            farSsl.add((leafCount, cand, base));
          case _BaselineKind.sliverGrid:
            farGrid.add((leafCount, cand, base));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — far stitch vs ${_label(kind)} animateTo:\n'
          '  $cand\n  $base',
        );
      }
    });

    testWidgets('memory at rest — $leafCount leaves', (tester) async {
      final sections = generateCatalogSections(leafCount);

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();
      await tester.pumpWidget(
        _candidateApp(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final candMem = CatalogMemorySnapshot(
        label: 'PCV rest ($leafCount)',
        attachedLeaves: _candidateRender(tester).attachedLeafCount,
        renderObjectCount: _renderObjectCount(tester),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        await tester.pumpWidget(
          _baselineApp(kind: kind, sections: sections, scrollController: sc),
        );
        await tester.pumpAndSettle();
        final baseMem = CatalogMemorySnapshot(
          label: '${_label(kind)} rest ($leafCount)',
          visibleCells: _glyphCellCount(tester),
          renderObjectCount: _renderObjectCount(tester),
        );
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        switch (kind) {
          case _BaselineKind.superSliver:
            memRestSsl.add((leafCount, candMem, baseMem));
          case _BaselineKind.sliverGrid:
            memRestGrid.add((leafCount, candMem, baseMem));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — memory rest vs ${_label(kind)}:\n'
          '  $candMem\n  $baseMem',
        );
      }
    });

    testWidgets('memory after scroll-through — $leafCount leaves', (
      tester,
    ) async {
      final sections = generateCatalogSections(leafCount);

      final dataSource = FakeCatalogDataSource(sections: sections);
      final assetCache = FakeCatalogAssetCache();
      final controller = PanelCatalogController();
      await tester.pumpWidget(
        _candidateApp(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final candRo = _candidateRender(tester);
      final candMax = candRo.maxOffset;
      var peakAttached = candRo.attachedLeafCount;
      var candPeakRo = _renderObjectCount(tester);
      const steps = 64;
      for (var i = 0; i <= steps; i++) {
        controller.jumpTo(candMax * i / steps);
        await tester.pump();
        final n = candRo.attachedLeafCount;
        final ros = _renderObjectCount(tester);
        if (n > peakAttached) peakAttached = n;
        if (ros > candPeakRo) candPeakRo = ros;
      }
      final candMem = CatalogMemorySnapshot(
        label: 'PCV scroll ($leafCount)',
        attachedLeaves: peakAttached,
        renderObjectCount: candPeakRo,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      dataSource.dispose();
      controller.dispose();

      for (final kind in _BaselineKind.values) {
        final sc = ScrollController();
        await tester.pumpWidget(
          _baselineApp(kind: kind, sections: sections, scrollController: sc),
        );
        await tester.pumpAndSettle();
        final maxExtent = sc.position.maxScrollExtent;
        var peakCells = _glyphCellCount(tester);
        var basePeakRo = _renderObjectCount(tester);
        for (var i = 0; i <= steps; i++) {
          sc.jumpTo(maxExtent * i / steps);
          await tester.pump();
          final cells = _glyphCellCount(tester);
          final ros = _renderObjectCount(tester);
          if (cells > peakCells) peakCells = cells;
          if (ros > basePeakRo) basePeakRo = ros;
        }
        final baseMem = CatalogMemorySnapshot(
          label: '${_label(kind)} scroll ($leafCount)',
          visibleCells: peakCells,
          renderObjectCount: basePeakRo,
        );
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        switch (kind) {
          case _BaselineKind.superSliver:
            memScrollSsl.add((leafCount, candMem, baseMem));
          case _BaselineKind.sliverGrid:
            memScrollGrid.add((leafCount, candMem, baseMem));
        }
        // ignore: avoid_print
        print(
          '\n$leafCount leaves — memory scroll vs ${_label(kind)}:\n'
          '  $candMem\n  $baseMem',
        );
      }
    });
  }

  tearDownAll(() {
    void dump(
      String title,
      List<(int, BenchmarkMetrics, BenchmarkMetrics)> ssl,
      List<(int, BenchmarkMetrics, BenchmarkMetrics)> grid,
    ) {
      // ignore: avoid_print
      print(
        generateCatalogComparisonTable(
          title: '$title — vs SuperSliverList',
          rows: ssl,
        ),
      );
      // ignore: avoid_print
      print(
        generateCatalogComparisonTable(
          title: '$title — vs SliverGrid',
          rows: grid,
          baselineLabel: 'SliverGrid + cells',
        ),
      );
    }

    // ignore: avoid_print
    print('\n${'=' * 70}');
    dump('Forced layout', layoutSsl, layoutGrid);
    dump('Scroll-only paint', paintSsl, paintGrid);
    dump('Fling frame time', flingSsl, flingGrid);
    dump('Near-path section jump', nearSsl, nearGrid);
    dump('Far-path stitch vs animateTo', farSsl, farGrid);
    // ignore: avoid_print
    print(
      generateCatalogMemoryTable(
        title: 'Memory at rest — vs SuperSliverList',
        rows: memRestSsl,
      ),
    );
    // ignore: avoid_print
    print(
      generateCatalogMemoryTable(
        title: 'Memory at rest — vs SliverGrid',
        rows: memRestGrid,
        baselineLabel: 'SliverGrid + cells',
      ),
    );
    // ignore: avoid_print
    print(
      generateCatalogMemoryTable(
        title: 'Memory peak scroll-through — vs SuperSliverList',
        rows: memScrollSsl,
      ),
    );
    // ignore: avoid_print
    print(
      generateCatalogMemoryTable(
        title: 'Memory peak scroll-through — vs SliverGrid',
        rows: memScrollGrid,
        baselineLabel: 'SliverGrid + cells',
      ),
    );
  });
}
