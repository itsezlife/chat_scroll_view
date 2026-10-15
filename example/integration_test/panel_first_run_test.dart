import 'dart:io';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

import 'panel_perf/acceptance.dart';
import 'panel_perf/panel_harness.dart';
import 'panel_perf/report.dart';
import 'panel_perf/scenario_support.dart';

/// On-device acceptance test for the emoji cache flows (baked-atlas ticket 09).
///
/// One launch runs three scenarios against one cache directory that is created
/// empty for the launch, so the first is genuinely a first run:
///
/// | Report key                | Asserted | What it isolates                       |
/// | ------------------------- | -------- | -------------------------------------- |
/// | `first_run_no_cache`      | yes      | no cache: circles while the atlas bakes; zero dropped frames still required |
/// | `cold_start_valid_cache`  | yes      | a new atlas over the pages the first run persisted: circles at most 500 ms, open animation drops no frame |
/// | `os_update_stale_rebake`  | no       | the art version changed: old pages stay drawn, new set bakes behind them, one swap |
///
/// Circles are allowed for as long as they last in the first scenario; the bar
/// there is frames. The second scenario simulates a later launch by tearing the
/// panel down and mounting a new one over the same directory: the atlas, its
/// resident pages and its decisions are new, and only the disk is shared. It
/// does not make the engine forget what it rasterised, so the strict cold
/// start is the three-fresh-launch run with the cache directory kept (see the
/// QA steps in `docs/panel-catalog/qa-glyph-cache.md`).
///
/// Verdict extras on top of the frame criteria: the first scenario must end
/// with the pages persisted, the second must be a cache hit that restored
/// every page inside [kCachedCircleBudget] (measured from the atlas start, a
/// stricter point than the panel opening). Both are skipped where the platform
/// bakes nothing.
///
/// The art version is `EMOJI_ART_VERSION` (default `suite`); the diagnostic
/// scenario runs with that value plus `-updated`, which is how an OS update is
/// simulated without a plugin.
///
/// Run three fresh launches with
/// `dart run tool/panel_perf.dart --suite first_run <device-id> <label>`, in
/// `--profile`; only the reference device gates.
const _artVersion = String.fromEnvironment(
  'EMOJI_ART_VERSION',
  defaultValue: 'suite',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('emoji cache flows meet the frame budget', (tester) async {
    final dir = Directory.systemTemp.createTempSync('glyph_first_run_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final reports = <ScenarioReport>[];

    // --- First run: nothing on disk. ---
    var harness = await _mount(tester, dir, _artVersion);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    var report = await measureScenario(
      tester,
      binding,
      kFirstRunScenario,
      asserted: true,
      body: () async {
        harness.open();
        await tester.pump();
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 800));
        return flingPass(tester);
      },
    );
    // The bake may still be going; the cache is judged once it is done.
    final firstRunFailures = <String>[];
    if (_atlasOf(tester) != null) {
      await _untilAllPages(tester);
      final persisted = await tester.runAsync(
        () => _persistedPages(dir, _artVersion),
      );
      if (persisted != _atlasOf(tester)!.index.pageCount) {
        firstRunFailures.add(
          'the first run persisted $persisted of '
          '${_atlasOf(tester)!.index.pageCount} pages',
        );
      }
    }
    reports.add(_with(report, firstRunFailures));
    await _unmount(tester, harness);

    // --- A later launch: same disk, everything else new. ---
    harness = await _mount(tester, dir, _artVersion);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    report = await measureScenario(
      tester,
      binding,
      kCachedColdStartScenario,
      asserted: true,
      body: () async {
        harness.open();
        await tester.pump();
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 800));
        return null;
      },
    );
    final coldFailures = <String>[];
    final cold = _atlasOf(tester)?.cacheReport;
    if (cold != null) {
      if (cold.verdict != GlyphCacheVerdict.hit) {
        coldFailures.add('expected a cache hit, got ${cold.verdict}');
      }
      final visible = cold.allPagesAfterStart;
      if (visible == null || visible > kCachedCircleBudget) {
        coldFailures.add(
          'circles lasted ${visible?.inMilliseconds} ms from the atlas start '
          '(allowed ${kCachedCircleBudget.inMilliseconds} ms)',
        );
      }
    }
    reports.add(_with(report, coldFailures));
    await _unmount(tester, harness);

    // --- The launch after an OS update: the art version changed. ---
    harness = await _mount(tester, dir, '$_artVersion-updated');
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    report = await measureScenario(
      tester,
      binding,
      kOsUpdateScenario,
      asserted: false,
      body: () async {
        harness.open();
        await tester.pump();
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 800));
        final coverage = await flingPass(tester);
        if (_atlasOf(tester) != null) await _untilAllPages(tester);
        return coverage;
      },
    );
    reports.add(_with(report, const []));
    await _unmount(tester, harness);

    publishAndAssert(binding, reports);
  });
}

Future<PanelHarness> _mount(WidgetTester tester, Directory dir, String art) =>
    PanelHarness.start(
      tester,
      glyphCache: createGlyphCacheStoreForPlatform(dir.path),
      glyphArtVersion: FixedGlyphArtVersion(art),
    );

Future<void> _unmount(WidgetTester tester, PanelHarness harness) async {
  harness.dispose();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
}

/// The viewport's atlas, or null when the platform bakes nothing.
GlyphAtlas? _atlasOf(WidgetTester tester) {
  final finder = find.byType(PanelCatalogViewport);
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<PanelCatalogViewport>(finder).assetCache.glyphAtlas;
}

/// Pumps until the atlas has every page drawable, or 30 s pass.
Future<void> _untilAllPages(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (_atlasOf(tester)?.cacheReport.allPagesAfterStart == null &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pages a later launch would find, committed under [art], read from disk.
Future<int> _persistedPages(Directory dir, String art) async {
  final store = createGlyphCacheStoreForPlatform(dir.path);
  final committed = await store.openCommitted();
  if (committed == null || committed.record.key.artVersion != art) return 0;
  var pages = 0;
  for (var page = 0; page < 64; page++) {
    final image = await committed.pages.read(page);
    if (image == null) break;
    image.dispose();
    pages++;
  }
  return pages;
}

/// [report] with [extra] failures added to its verdict (and nothing else).
ScenarioReport _with(ScenarioReport report, List<String> extra) {
  if (extra.isEmpty) return report;
  return ScenarioReport(
    scenario: report.scenario,
    asserted: report.asserted,
    meta: report.meta,
    samples: report.samples,
    stats: report.stats,
    verdict: Verdict([...report.verdict.failures, ...extra]),
    coverage: report.coverage,
  );
}
