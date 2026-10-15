import 'dart:math' as math;

import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/panel_catalog_perf_probe.dart';

/// Fast-fling frame timing for the emoji keyboard panel, on a real device.
///
/// Hosts the real [KeyboardPanel] (strip, catalog viewport, bottom bar) without
/// the chat screen, so no backend is needed. Run with `tool/run_panel_perf.sh`
/// in `--profile`; debug numbers are meaningless for raster cost.
///
/// Scenarios run in order inside one process, so the engine's glyph atlas is
/// cold only for `cold_pass1`. Anything that needs a cold atlas (for example
/// `--dart-define=PANEL_PERF_SKIP_WARM=true`) is a separate run.
///
/// Each pass flings the whole catalog down and back up (`maxOffsetPx` in the
/// report proves coverage).
///
/// | Report key                | What it isolates                              |
/// | ------------------------- | --------------------------------------------- |
/// | `cold_pass1` (+ timeline) | first sight of every glyph, warm-up as shipped |
/// | `warm_pass2`              | same pass with every glyph already seen (also catches atlas eviction/rebuild) |
/// | `warm_pass3`              | repeat of pass2: run-to-run variance          |
/// | `reopen_pass4`            | panel closed and reopened: new paragraph cache, warm atlas |
///
/// Experiments that need a cold atlas are separate builds:
/// `PANEL_PERF_SKIP_WARM=true` (no warm-up), `PANEL_PERF_GLYPH=A` (Latin letter
/// instead of emoji).
/// `traceAction` reaches the VM service over `localhost`, which a USB-attached
/// device refuses (`Connection refused`), so the timeline is opt-in:
/// `--dart-define=PANEL_PERF_TIMELINE=true`. `FrameTiming` always runs.
const _traceTimeline = bool.fromEnvironment('PANEL_PERF_TIMELINE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // Real vsync cadence; the default policy would pump on demand and hide
    // scheduling cost.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('panel catalog fast fling', (tester) async {
    final harness = await _PanelHarness.start(tester);

    // Let the open animation and `warmAhead` finish, as a user's first fling
    // would typically come a moment after the panel appears.
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 800));

    for (final name in const ['cold_pass1', 'warm_pass2', 'warm_pass3']) {
      PanelCatalogPerfProbe.resetCoverage();
      await _scenario(
        tester,
        binding,
        name,
        timeline: _traceTimeline && name == 'cold_pass1',
        body: () => _flingPass(tester),
      );
    }

    harness.dispose();

    // Close and reopen: a new render object starts with an empty paragraph
    // cache while the engine's glyph atlas stays warm. Isolates the cost the
    // panel pays on every open, separate from first sight of a glyph.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    final reopened = await _PanelHarness.start(tester);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
    PanelCatalogPerfProbe.resetCoverage();
    await _scenario(
      tester,
      binding,
      'reopen_pass4',
      body: () => _flingPass(tester),
    );
    reopened.dispose();
  });
}

/// Whole catalog, down then back up: chained flings until the far end is
/// reached, then until the top is. Chained so each lands while the last coasts.
Future<void> _flingPass(WidgetTester tester) async {
  final viewport = find.byType(PanelCatalogViewport);
  Future<void> fling(double dy) async {
    await tester.fling(viewport, Offset(0, dy), 7000);
    await tester.pump(const Duration(milliseconds: 250));
  }

  const cap = 80;
  for (var i = 0; i < cap && !_atEnd; i++) {
    await fling(-300);
  }
  await _settle(tester);
  for (var i = 0; i < cap && PanelCatalogPerfProbe.lastOffset > 50; i++) {
    await fling(300);
  }
  await _settle(tester);
}

bool get _atEnd =>
    PanelCatalogPerfProbe.contentExtent > 0 &&
    PanelCatalogPerfProbe.lastOffset >=
        PanelCatalogPerfProbe.contentExtent -
            PanelCatalogPerfProbe.viewportHeight -
            50;

/// Pumps until no frame is scheduled (fling finished) or 15 s pass.
Future<void> _settle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  do {
    await tester.pump(const Duration(milliseconds: 16));
  } while (tester.binding.hasScheduledFrame &&
      DateTime.now().isBefore(deadline));
}

Future<void> _scenario(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name, {
  required Future<void> Function() body,
  bool timeline = false,
}) async {
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

  // Timings are delivered in batches; give the last one time to arrive.
  await tester.pump(const Duration(milliseconds: 1500));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);

  final view = tester.view;
  final refreshRate = view.display.refreshRate;
  final report = _summarize(
    timings,
    budgetMs: 1000 / refreshRate,
    meta: {
      'scenario': name,
      'mode': switch ((kReleaseMode, kProfileMode)) {
        (true, _) => 'release',
        (_, true) => 'profile',
        _ => 'debug',
      },
      'platform': defaultTargetPlatform.name,
      'refreshRateHz': refreshRate,
      'devicePixelRatio': view.devicePixelRatio,
      'physicalSize': '${view.physicalSize.width}x${view.physicalSize.height}',
      'skipWarmAhead': PanelCatalogPerfProbe.skipWarmAhead,
      'glyphOverride': PanelCatalogPerfProbe.glyphOverride,
      'maxOffsetPx': PanelCatalogPerfProbe.maxOffset,
      'contentExtentPx': PanelCatalogPerfProbe.contentExtent,
      'viewportHeightPx': PanelCatalogPerfProbe.viewportHeight,
    },
  );
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![name] = report;
  debugPrint('[panel-perf] $name ${report['summary']}');
}

Map<String, dynamic> _summarize(
  List<FrameTiming> frames, {
  required double budgetMs,
  required Map<String, Object?> meta,
}) {
  double ms(Duration d) => d.inMicroseconds / 1000;
  final build = frames.map((f) => ms(f.buildDuration)).toList();
  final raster = frames.map((f) => ms(f.rasterDuration)).toList();
  final total = frames.map((f) => ms(f.totalSpan)).toList();

  Map<String, double> stats(List<double> v) {
    if (v.isEmpty) return const {};
    final s = [...v]..sort();
    double q(double p) => s[math.min(s.length - 1, (p * s.length).floor())];
    return {
      'p50': q(0.5),
      'p90': q(0.9),
      'p99': q(0.99),
      'max': s.last,
      'mean': s.reduce((a, b) => a + b) / s.length,
    };
  }

  var jank = 0;
  var severe = 0;
  for (var i = 0; i < frames.length; i++) {
    final worst = math.max(build[i], raster[i]);
    if (worst > budgetMs) jank++;
    if (worst > budgetMs * 2) severe++;
  }

  return {
    'meta': meta,
    'summary': {
      'frames': frames.length,
      'budgetMs': budgetMs,
      'jankFrames': jank,
      'severeFrames(>2x)': severe,
      'buildMs': stats(build),
      'rasterMs': stats(raster),
      'totalSpanMs': stats(total),
    },
    // Per-frame series, in delivery order, to correlate with the timeline.
    'frames': {
      'buildMs': build.map((v) => double.parse(v.toStringAsFixed(3))).toList(),
      'rasterMs': raster
          .map((v) => double.parse(v.toStringAsFixed(3)))
          .toList(),
      'totalSpanMs': total
          .map((v) => double.parse(v.toStringAsFixed(3)))
          .toList(),
    },
  };
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
    controller.open(landscape: false);
    await tester.pump();
    return _PanelHarness._(store, inset, controller, data);
  }

  void dispose() {
    controller.dispose();
    inset.dispose();
    data.dispose();
  }
}
