import 'dart:math' as math;

import 'package:chat_wallpaper/chat_wallpaper_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../panel_perf/acceptance.dart';
import '../panel_perf/frame_metrics.dart';
import '../panel_perf/report.dart';

/// Raster work the wallpaper did during one scenario.
typedef WallpaperWork = ({int patternRasterizations, int gradientRasters});

/// What a scenario requires beyond being measured: returns the broken rules,
/// empty when it holds.
typedef WallpaperRule =
    List<String> Function(FrameStats stats, WallpaperWork work);

/// Requires every frame to fit one vsync budget, as the panel suites do.
List<String> withinFrameBudget(FrameStats stats, WallpaperWork work) =>
    judge(stats).failures;

/// Requires a scenario that only changes the window's size to rasterize
/// nothing: neither the pattern (rasterized once per display) nor the
/// gradient (a fixed raster drawn cover-fit).
List<String> resizesWithoutRaster(FrameStats stats, WallpaperWork work) => [
  if (work.patternRasterizations > 0)
    '${work.patternRasterizations} pattern rasterizations on a resize',
  if (work.gradientRasters > 0)
    '${work.gradientRasters} gradient rasters on a resize',
];

/// Runs [body] while recording every frame and the wallpaper's raster work.
///
/// Every scenario is reported. Its verdict holds the failures of [rules];
/// the run fails on it only when [asserted]. A scenario without rules is a
/// measurement: its verdict always passes.
Future<ScenarioReport> measureWallpaperScenario(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name, {
  required Future<void> Function() body,
  bool asserted = false,
  List<WallpaperRule> rules = const [],
  bool timeline = false,
}) async {
  ChatWallpaperDiagnostics.reset();
  final timings = <FrameTiming>[];
  void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(onTimings);

  if (timeline) {
    await binding.traceAction(
      body,
      streams: const ['Dart', 'Embedder', 'GC'],
      reportKey: '${name}_timeline',
    );
  } else {
    await body();
  }
  final work = (
    patternRasterizations: ChatWallpaperDiagnostics.patternRasterizations,
    gradientRasters: ChatWallpaperDiagnostics.gradientRasters,
  );

  // Timings are delivered in batches; give the last one time to arrive.
  await tester.pump(const Duration(milliseconds: 1500));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);

  final view = tester.view;
  final refreshRate = view.display.refreshRate;
  double ms(Duration d) => d.inMicroseconds / 1000;
  final samples = [
    for (final t in timings)
      FrameSample(
        buildMs: ms(t.buildDuration),
        rasterMs: ms(t.rasterDuration),
        totalMs: ms(t.totalSpan),
      ),
  ];
  final budgetMs = vsyncBudgetMs(refreshRate);
  final stats = FrameStats.of(samples, budgetMs: budgetMs);
  // Vsync to raster finish. Work the raster thread does outside a frame
  // (an image snapshot, a texture upload) is in no frame's raster time; the
  // frames it delays show here, finishing late.
  final spans = [for (final s in samples) s.totalMs];
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
      'displaySize': '${view.display.size.width}x${view.display.size.height}',
      'patternRasterizations': work.patternRasterizations,
      'gradientRasters': work.gradientRasters,
      'lateFrames': spans.where((t) => t > budgetMs * 2).length,
      'spanP99Ms': spans.isEmpty ? 0 : percentile(spans, 0.99),
      'spanMaxMs': spans.isEmpty ? 0 : spans.reduce(math.max),
    },
    samples: samples,
    stats: stats,
    verdict: Verdict([for (final rule in rules) ...rule(stats, work)]),
  );
}

/// Publishes [reports] through the binding, prints one line per scenario
/// with the wallpaper's raster work, and fails when an asserted one did not
/// pass. Publishes first, so a red run still leaves its numbers.
void publishWallpaperReports(
  IntegrationTestWidgetsFlutterBinding binding,
  List<ScenarioReport> reports,
) {
  binding.reportData = {
    ...?binding.reportData,
    for (final report in reports) report.scenario: report.toJson(),
  };
  for (final report in reports) {
    final s = report.stats;
    final m = report.meta;
    debugPrint(
      '[wallpaper-perf] ${report.scenario}: ${s.frames} frames, '
      '${s.overBudgetFrames} over ${s.budgetMs.toStringAsFixed(1)} ms '
      '(${s.severeFrames} severe), build p99 '
      '${s.buildP99Ms.toStringAsFixed(1)} max '
      '${s.buildMaxMs.toStringAsFixed(1)}, raster p50 '
      '${s.rasterP50Ms.toStringAsFixed(1)} p99 '
      '${s.rasterP99Ms.toStringAsFixed(1)} max '
      '${s.rasterMaxMs.toStringAsFixed(1)} ms; ${m['lateFrames']} late, '
      'span p99 ${(m['spanP99Ms']! as double).toStringAsFixed(1)} max '
      '${(m['spanMaxMs']! as double).toStringAsFixed(1)} ms; pattern '
      '${m['patternRasterizations']}, '
      'gradients ${m['gradientRasters']}'
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
