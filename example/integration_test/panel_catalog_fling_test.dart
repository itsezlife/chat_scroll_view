import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

import 'panel_perf/acceptance.dart';
import 'panel_perf/frame_metrics.dart';
import 'panel_perf/report.dart';

/// On-device acceptance test for the emoji keyboard panel (bare panel).
///
/// The user's "native-like" bar as a test: the panel open animation and the
/// cold first fling over the whole catalogue must drop no frame over one vsync
/// budget (derived from the display's refresh rate) and keep raster p99 at most
/// 2 ms. Today it fails; the numbers it prints are the baseline.
///
/// Hosts the real [KeyboardPanel] (strip, catalog viewport, bottom bar) without
/// the chat screen, so no backend is needed. Run three fresh launches with
/// `dart run tool/panel_perf.dart <device-id> <label>`, in `--profile`; debug
/// numbers are meaningless for raster cost.
///
/// Depends only on the public panel and chrome APIs: no experiment switches or
/// prototype code.
///
/// | Report key         | Asserted | What it isolates                          |
/// | ------------------ | -------- | ----------------------------------------- |
/// | `panel_open`       | yes      | open animation, first paint of the panel  |
/// | `cold_first_pass`  | yes      | first sight of every glyph, whole catalogue down and back up |
/// | `warm_pass2`       | no       | same pass with every glyph already seen   |
/// | `reopen_pass4`     | no       | panel closed and reopened: new paragraph cache, warm atlas |
///
/// Scenarios run in order inside one process, so the engine's glyph atlas is
/// cold only for `panel_open` and `cold_first_pass`: every verdict needs a
/// fresh launch. Reports are written before any assertion, so a red run still
/// leaves its numbers behind.
///
/// `traceAction` reaches the VM service over `localhost`, which a USB-attached
/// device refuses (`Connection refused`), so the timeline is opt-in:
/// `--dart-define=PANEL_PERF_TIMELINE=true`. `FrameTiming` always runs.
const _traceTimeline = bool.fromEnvironment('PANEL_PERF_TIMELINE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // Real vsync cadence; the default policy would pump on demand and hide
    // scheduling cost.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('panel catalog cold first pass meets the frame budget', (
    tester,
  ) async {
    final reports = <ScenarioReport>[];

    // The app shell is up and the panel closed before measuring starts: the
    // open animation is the first thing a user's tap would trigger.
    final harness = await _PanelHarness.start(tester);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    reports.add(
      await _scenario(
        tester,
        binding,
        kPanelOpenScenario,
        asserted: true,
        body: () async {
          harness.open();
          await tester.pump();
          await _settle(tester);
          // As a user's first fling comes a moment after the panel appears.
          await tester.pump(const Duration(milliseconds: 800));
          return null;
        },
      ),
    );

    reports.add(
      await _scenario(
        tester,
        binding,
        kColdFirstPassScenario,
        asserted: true,
        timeline: _traceTimeline,
        body: () => _flingPass(tester),
      ),
    );

    reports.add(
      await _scenario(
        tester,
        binding,
        'warm_pass2',
        asserted: false,
        body: () => _flingPass(tester),
      ),
    );

    harness.dispose();

    // Close and reopen: a new render object starts with an empty paragraph
    // cache while the engine's glyph atlas stays warm. Isolates the cost the
    // panel pays on every open, separate from first sight of a glyph.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    final reopened = await _PanelHarness.start(tester);
    reopened.open();
    await tester.pump();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
    reports.add(
      await _scenario(
        tester,
        binding,
        'reopen_pass4',
        asserted: false,
        body: () => _flingPass(tester),
      ),
    );
    reopened.dispose();

    // Publish before asserting: the driver writes reports even when red.
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
  });
}

/// Whole catalogue, down then back up: chained flings until the offset stops
/// advancing (the end), then until the top is reached. Chained so each lands
/// while the last coasts. Returns the evidence that it travelled that far.
Future<FlingCoverage> _flingPass(WidgetTester tester) async {
  final finder = find.byType(PanelCatalogViewport);
  final viewport = tester.widget<PanelCatalogViewport>(finder);
  final controller = viewport.controller;
  final viewportHeight = tester.getSize(finder).height;

  var maxOffset = 0.0;
  void track(PanelCatalogScrollEvent _) {
    if (controller.offset > maxOffset) maxOffset = controller.offset;
  }

  controller.addScrollListener(track);
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
  await _settle(tester);
  for (var i = 0; i < cap && controller.offset > 50; i++) {
    await fling(300);
  }
  await _settle(tester);
  controller.removeScrollListener(track);

  return FlingCoverage(
    reachedEnd: reachedEnd,
    returnedToTop: controller.offset <= 50,
    maxOffsetPx: maxOffset,
    viewportHeightPx: viewportHeight,
    expectedExtentPx: estimateContentExtent(
      leavesPerSection: [
        for (final section in viewport.dataSource.sections)
          section.leaves.length,
      ],
      spanCount: viewport.spanCount,
      cellExtent: viewport.cellExtent,
      headerExtent: viewport.headerExtent,
    ),
  );
}

/// Pumps until no frame is scheduled (fling finished) or 15 s pass.
Future<void> _settle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  do {
    await tester.pump(const Duration(milliseconds: 16));
  } while (tester.binding.hasScheduledFrame &&
      DateTime.now().isBefore(deadline));
}

/// Runs [body] while recording every frame, and judges the result.
///
/// [body] returns fling coverage when it flings; a scenario that returns it is
/// also required to have covered the catalogue.
Future<ScenarioReport> _scenario(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name, {
  required bool asserted,
  required Future<FlingCoverage?> Function() body,
  bool timeline = false,
}) async {
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
    },
    samples: samples,
    stats: stats,
    verdict: judge(stats, coverage: coverage),
    coverage: coverage,
  );
}

/// Real [KeyboardPanel] on a bare scaffold: no chat, no backend.
final class _PanelHarness {
  _PanelHarness._(this.store, this.inset, this.controller, this.data);

  final KeyboardPanelStore store;
  final ChatBottomInsetController inset;
  final KeyboardPanelController controller;
  final DefaultEmojiDataSource data;

  static Future<_PanelHarness> start(WidgetTester tester) async {
    final store = KeyboardPanelStore(defaultHeight: 380);
    final data = DefaultEmojiDataSource(
      catalog: LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        categoryTitles: EmojiCategoryTitles.russian,
        stripIconFor: EmojiTabAssets.stripIconForId,
      ),
    );
    await (store.load(), data.load()).wait;
    final inset = ChatBottomInsetController(store: store);
    final controller = KeyboardPanelController(inset: inset, store: store);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => ChatChromeTheme(
          colors: const ChatChromeColors.dark(),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<double>(
              valueListenable: inset.heightListenable,
              builder: (context, height, child) =>
                  SizedBox(height: height, child: child),
              child: RepaintBoundary(
                child: KeyboardPanel(
                  controller: controller,
                  allow: KeyboardPanelAllow.emojiOnly,
                  labels: KeyboardPanelLabels.russian,
                  dataSource: data,
                  onEmojiSelected: (_) {},
                  onBackspace: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return _PanelHarness._(store, inset, controller, data);
  }

  void open() => controller.open(landscape: false);

  void dispose() {
    controller.dispose();
    inset.dispose();
    data.dispose();
  }
}
