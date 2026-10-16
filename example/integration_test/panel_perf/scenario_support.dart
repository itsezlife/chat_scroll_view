/// Measurement steps shared by the on-device panel acceptance tests, so every
/// suite flings, records and judges the same way.
library;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';

import 'acceptance.dart';
import 'frame_metrics.dart';
import 'report.dart';

/// Whole catalogue, down then back up: chained flings until the offset stops
/// advancing (the end), then until the top is reached. Chained so each lands
/// while the last coasts. Returns the evidence that it travelled that far.
Future<FlingCoverage> flingPass(WidgetTester tester) async {
  final finder = find.byType(PanelCatalogViewport);
  final viewport = tester.widget<PanelCatalogViewport>(finder);
  final controller = viewport.controller;
  final viewportHeight = tester.getSize(finder).height;

  var maxOffset = 0.0;
  void track(PanelCatalogScrollEvent _) {
    if (controller.offset > maxOffset) maxOffset = controller.offset;
  }

  controller.events.addListener(track);
  Future<void> fling(double dy) async {
    await tester.fling(finder, Offset(0, dy), 7000);
    await tester.pump(const Duration(milliseconds: 250));
  }

  const cap = 120;
  // At the end when two flings in a row no longer move the offset.
  var stalled = 0;
  for (var i = 0; i < cap && stalled < 2; i++) {
    final before = controller.offset;
    await fling(-300);
    stalled = (controller.offset - before).abs() < 1 ? stalled + 1 : 0;
  }
  final reachedEnd = stalled >= 2;
  await settle(tester);
  for (var i = 0; i < cap && controller.offset > 50; i++) {
    await fling(300);
  }
  await settle(tester);
  controller.events.removeListener(track);

  return FlingCoverage(
    reachedEnd: reachedEnd,
    returnedToTop: controller.offset <= 50,
    maxOffsetPx: maxOffset,
    viewportHeightPx: viewportHeight,
    expectedExtentPx: _expectedExtent(viewport),
  );
}

/// The content extent the viewport lays out, from what each section says of
/// its own grid (a page sets its geometry per section; the viewport's props are
/// only the default of a section that says nothing).
double _expectedExtent(PanelCatalogViewport viewport) {
  var extent = 0.0;
  for (final section in viewport.snapshots.value.sections) {
    final grid = section.layout is SectionLayout$Grid
        ? section.layout! as SectionLayout$Grid
        : null;
    extent += estimateContentExtent(
      leavesPerSection: [section.leaves.length],
      spanCount: grid?.spanCount ?? viewport.spanCount,
      cellExtent: grid?.cellExtent ?? viewport.cellExtent,
      headerExtent: grid?.headerExtent ?? viewport.headerExtent,
    );
  }
  return extent;
}

/// Pumps until no frame is scheduled (fling finished) or 15 s pass.
Future<void> settle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  do {
    await tester.pump(const Duration(milliseconds: 16));
  } while (tester.binding.hasScheduledFrame &&
      DateTime.now().isBefore(deadline));
}

/// Runs [body] while recording every frame, and judges the result.
///
/// [body] returns fling coverage when it flings; a scenario that returns it is
/// also required to have covered the catalogue. [requireBaked] additionally
/// requires the catalogue to be drawable from baked pages when the scenario
/// ends (see [BakeCoverage]): set it for a fling that is meant to run over
/// sprites. It is ignored where nothing is baked (the web).
Future<ScenarioReport> measureScenario(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name, {
  required bool asserted,
  required Future<FlingCoverage?> Function() body,
  bool timeline = false,
  bool requireBaked = false,
}) async {
  // Counts glyph paragraphs drawn as text during this scenario only.
  PanelCatalogDiagnostics.reset();
  final timings = <FrameTiming>[];
  void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(onTimings);

  FlingCoverage? coverage;
  if (timeline) {
    await binding.traceAction(
      () async => coverage = await body(),
      streams: const ['Dart', 'Embedder', 'GC'],
      reportKey: '${name}_timeline',
    );
  } else {
    coverage = await body();
  }

  // Timings are delivered in batches; give the last one time to arrive.
  await tester.pump(const Duration(milliseconds: 1500));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);

  final view = tester.view;
  final refreshRate = view.display.refreshRate;
  final budgetMs = vsyncBudgetMs(refreshRate);
  double ms(Duration d) => d.inMicroseconds / 1000;
  final samples = [
    for (final t in timings)
      FrameSample(
        buildMs: ms(t.buildDuration),
        rasterMs: ms(t.rasterDuration),
        totalMs: ms(t.totalSpan),
      ),
  ];
  final stats = FrameStats.of(samples, budgetMs: budgetMs);
  final paragraphDraws = PanelCatalogDiagnostics.glyphParagraphDraws;
  final atlasInfo = atlasMeta(tester);
  final shown = atlasInfo['atlasShownGlyphs'] as int?;
  final baked = atlasInfo['atlasBakedGlyphs'] as int?;
  final verdict = judge(
    stats,
    coverage: coverage,
    residentBytes: atlasInfo['atlasResidentBytes'] as int?,
    bake: requireBaked && shown != null && baked != null
        ? BakeCoverage(bakedGlyphs: baked, shownGlyphs: shown)
        : null,
  );
  return ScenarioReport(
    scenario: name,
    asserted: asserted,
    meta: {
      'mode': switch ((kReleaseMode, kProfileMode)) {
        (true, _) => 'release',
        (_, true) => 'profile',
        _ => 'debug',
      },
      'platform': defaultTargetPlatform.name,
      'refreshRateHz': refreshRate,
      'devicePixelRatio': view.devicePixelRatio,
      'physicalSize': '${view.physicalSize.width}x${view.physicalSize.height}',
      // The marker that emoji are drawn from baked pages: on a platform that
      // bakes, no glyph is ever drawn as text at scroll time.
      'glyphParagraphDraws': paragraphDraws,
      ...atlasInfo,
    },
    samples: samples,
    stats: stats,
    verdict: kIsWeb || paragraphDraws == 0
        ? verdict
        : Verdict([
            ...verdict.failures,
            '$paragraphDraws glyphs were drawn as text; emoji must be drawn '
                'from baked atlas pages on this platform',
          ]),
    coverage: coverage,
  );
}

/// How much of the catalogue the viewport's atlas had baked when the scenario
/// ended: `atlasGlyphs` planned, `atlasShownGlyphs` the distinct glyphs the
/// viewport shows, `atlasBakedGlyphs` of those drawable. Empty when the panel
/// is not mounted or the platform bakes nothing. Circles are allowed while a
/// first run bakes, so a scenario judges these only when it asks for it
/// (`requireBaked`).
///
/// `atlasResidentBytes` is what the atlas holds right now, resident pages and
/// the stale set still drawn (raw RGBA, mip levels excluded), and
/// `atlasResidentPages` the resident page count; the scenario's verdict holds
/// the bytes to the 64 MiB ceiling. They are read once, when the scenario ends,
/// so they do not show the peak of a rebake that held two sets.
Map<String, Object?> atlasMeta(WidgetTester tester) {
  final finder = find.byType(PanelCatalogViewport);
  if (finder.evaluate().isEmpty) return const {};
  // The harness composed the scope with an atlas as its glyph source.
  final atlas =
      tester.widget<PanelCatalogViewport>(finder).assets.glyphSource
          as GlyphAtlas?;
  if (atlas == null) return const {'atlas': 'none'};
  final glyphs = <String>{
    for (final section
        in tester.widget<PanelCatalogViewport>(finder).snapshots.value.sections)
      for (final leaf in section.leaves)
        if (leaf.key case ContentKey$Unicode(:final sequence)) sequence,
  };
  final cache = atlas.cacheReport;
  return {
    'atlasGlyphs': atlas.index.glyphCount,
    'atlasShownGlyphs': glyphs.length,
    'atlasBakedGlyphs': glyphs.where((g) => atlas.spriteOf(g) != null).length,
    'atlasResidentBytes': atlas.residentBytes,
    'atlasResidentPages': atlas.residency.residentPages.length,
    // Present only for an atlas with a persistent cache: what it decided and
    // how long the circles lasted, measured from the atlas start.
    if (cache.verdict != null) ...{
      'cacheVerdict': cache.verdict!.name,
      'cacheRestoredPages': cache.restoredPages,
      'cacheStalePages': cache.stalePages,
      'cacheSwapped': cache.swapped,
      'cacheFirstPageMs': cache.firstPageAfterStart?.inMilliseconds,
      'cacheAllPagesMs': cache.allPagesAfterStart?.inMilliseconds,
    },
  };
}

/// Publishes [reports] through the binding, prints one line per scenario and
/// fails when an asserted one did not pass.
///
/// Publishes before asserting: the driver writes reports even when red, so a
/// red run still leaves its numbers behind.
void publishAndAssert(
  IntegrationTestWidgetsFlutterBinding binding,
  List<ScenarioReport> reports,
) {
  binding.reportData = {
    ...?binding.reportData,
    for (final report in reports) report.scenario: report.toJson(),
  };
  for (final report in reports) {
    debugPrint(
      '[panel-perf] ${report.scenario} ${report.stats.frames} frames, '
      '${report.stats.overBudgetFrames} over budget, raster p99 '
      '${report.stats.rasterP99Ms.toStringAsFixed(2)} ms, max '
      '${report.stats.rasterMaxMs.toStringAsFixed(1)} ms'
      '${report.verdict.passed ? '' : ' -> ${report.verdict.failures.join('; ')}'}',
    );
  }

  final failures = [
    for (final report in reports)
      if (report.asserted && !report.verdict.passed)
        '${report.scenario}: ${report.verdict.failures.join('; ')}',
  ];
  expect(failures, isEmpty, reason: failures.join('\n'));
}
