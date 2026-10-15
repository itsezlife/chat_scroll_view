import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'panel_perf/frame_metrics.dart';

/// On-device check of the paced bake (baked-atlas ticket 06): the governor,
/// the visible-band priority and the pause rules, with the real system font
/// and the engine's own frame timings.
///
/// Five scenarios, each bakes the whole current catalogue with a
/// `GlyphBakeScheduler` on the real frame clock, next to cheap content (a
/// spinner, a sliding panel, a grid of Latin letters, so any dropped frame is
/// the bake's):
///
/// - `paced_idle`: the panel sits still. Ticket bar: no dropped frame at the
///   default pace. Also records when the page holding the last section lands
///   when it is prioritised (`visiblePageMs`) against the whole bake.
/// - `paced_open_paused` / `paced_open_unpaused`: the bake starts as the panel
///   slides open, with the pause rules on (the shipping behaviour) and off
///   (the evidence the prototype lacks: what a bake costs during the open
///   animation).
/// - `paced_fling_paused` / `paced_fling_unpaused`: the bake starts as a fling
///   begins, again with the rules on and off.
///
/// Each report holds the frame statistics over the whole scenario (motion plus
/// the bake that follows it), the bake wall time, when each page landed, and
/// the range the governor's pace took. With `PACED_BAKE_ENFORCE=true` a
/// scenario with the pause rules ON fails on any dropped frame; the unpaused
/// runs are recorded, never asserted. If an unpaused run drops frames and a
/// paused one does too, the pause rules need tightening (a longer settle, an
/// earlier signal) until the paused run is clean.
///
/// Run in `--profile` on the reference device (debug timings say nothing about
/// raster cost):
///
///   TARGET=integration_test/glyph_atlas_paced_bake_test.dart \
///   DEFINES="--dart-define=PACED_BAKE_ENFORCE=true" \
///   tool/run_panel_perf.sh DEVICE_ID LABEL
///
/// Only the reference device gates; elsewhere the numbers are indicative
/// (label them non-gating).
const _enforce = bool.fromEnvironment('PACED_BAKE_ENFORCE');

const _timeout = Duration(seconds: 30);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final glyphs = <String>{
    for (final category in emojiCatalogForLocale(const Locale('en')))
      for (final entry in category.entries) entry.glyph,
  }.toList();

  testWidgets('paced bake while idle', (tester) async {
    await _run(
      tester,
      binding,
      glyphs,
      name: 'paced_idle',
      pauseRules: true,
      prioritiseLastPage: true,
      motion: (host, startBake) async => startBake(),
    );
  });

  for (final pauseRules in [true, false]) {
    final rules = pauseRules ? 'paused' : 'unpaused';

    testWidgets('paced bake while the panel opens ($rules)', (tester) async {
      await _run(
        tester,
        binding,
        glyphs,
        name: 'paced_open_$rules',
        pauseRules: pauseRules,
        startOpen: false,
        motion: (host, startBake) async {
          startBake();
          host.opening.value = true;
          unawaited(host.slide.forward());
          while (!host.slide.isCompleted) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          host.opening.value = false;
        },
      );
    });

    testWidgets('paced bake while a fling runs ($rules)', (tester) async {
      await _run(
        tester,
        binding,
        glyphs,
        name: 'paced_fling_$rules',
        pauseRules: pauseRules,
        motion: (host, startBake) async {
          // The bake starts the instant the first fling does, so it
          // overlaps the motion instead of finishing before it.
          void startOnScroll() {
            if (!host.scrolling.value) return;
            host.scrolling.removeListener(startOnScroll);
            startBake();
          }

          host.scrolling.addListener(startOnScroll);
          for (var i = 0; i < 3; i++) {
            await tester.fling(
              find.byType(GridView),
              const Offset(0, -900),
              4000,
              warnIfMissed: false,
            );
            // Let the ballistic phase play out; the host's scroll signal
            // falls with it.
            await tester.pump(const Duration(milliseconds: 1200));
          }
        },
      );
    });
  }
}

// ---- scenario ------------------------------------------------------------------

Future<void> _run(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  List<String> glyphs, {
  required String name,
  required bool pauseRules,
  required Future<void> Function(_HostState host, VoidCallback startBake)
  motion,
  bool prioritiseLastPage = false,
  bool startOpen = true,
}) async {
  final host = GlobalKey<_HostState>();
  await tester.pumpWidget(_Host(key: host));
  await tester.pump(const Duration(milliseconds: 500));
  final state = host.currentState!;
  if (startOpen) state.slide.value = 1;

  final index = GlyphAtlasIndex(glyphs);
  final store = FakeGlyphPageStore();
  final baker = GlyphBaker(
    index: index,
    rasteriser: ParagraphGlyphRasteriser(),
    store: store,
  );
  final source = SchedulerBakeFrameSource(view: tester.view);
  final wall = Stopwatch();
  final landed = <Map<String, Object?>>[];
  // The unpaused run hands the scheduler signals that never change, so the
  // same motion happens and only the pause rules differ.
  final inert = ValueNotifier<bool>(false);
  final visible = ValueNotifier<bool>(true);
  final scheduler = GlyphBakeScheduler(
    baker: baker,
    frames: source,
    clock: () => wall.elapsed,
    signals: BakePauseSignals(
      panelVisible: visible,
      scrolling: pauseRules ? state.scrolling : inert,
      panelOpening: pauseRules ? state.opening : inert,
    ),
    onPageBaked: (page) =>
        landed.add({'page': page, 'atMs': wall.elapsedMilliseconds}),
  );

  // The last section sits on the last page: the farthest from where baking
  // would start, so the best test that priority works.
  final lastPage = index.pageCount - 1;
  if (prioritiseLastPage) scheduler.prioritise([glyphs.last]);

  final timings = <FrameTiming>[];
  void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(onTimings);

  var paceMin = scheduler.glyphsPerFrame;
  var paceMax = paceMin;
  void samplePace() {
    paceMin = math.min(paceMin, scheduler.glyphsPerFrame);
    paceMax = math.max(paceMax, scheduler.glyphsPerFrame);
  }

  await motion(state, () {
    wall.start();
    scheduler.start();
  });
  while (!scheduler.isComplete && wall.elapsed < _timeout) {
    await tester.pump(const Duration(milliseconds: 50));
    samplePace();
  }
  wall.stop();
  // Let the last frames report their timings.
  await tester.pump(const Duration(milliseconds: 1500));
  SchedulerBinding.instance.removeTimingsCallback(onTimings);

  final budget = vsyncBudgetMs(tester.view.display.refreshRate);
  final stats = FrameStats.of([
    for (final t in timings)
      FrameSample(
        buildMs: t.buildDuration.inMicroseconds / 1000,
        rasterMs: t.rasterDuration.inMicroseconds / 1000,
        totalMs: t.totalSpan.inMicroseconds / 1000,
      ),
  ], budgetMs: budget);

  final complete = scheduler.isComplete;
  scheduler.dispose();
  source.dispose();
  baker.dispose();
  await store.clear();
  inert.dispose();
  visible.dispose();

  final lastPageAt = landed
      .where((p) => p['page'] == lastPage)
      .map((p) => p['atMs'])
      .firstOrNull;
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![name] = {
    'meta': {
      'pauseRules': pauseRules,
      'glyphs': glyphs.length,
      'pages': index.pageCount,
      'refreshHz': tester.view.display.refreshRate,
      'dpr': tester.view.devicePixelRatio,
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      'platform': defaultTargetPlatform.name,
    },
    'summary': {
      'complete': complete,
      'bakeWallMs': wall.elapsedMilliseconds,
      'pagesLanded': landed,
      if (prioritiseLastPage) 'visiblePageMs': lastPageAt,
      'paceMin': paceMin,
      'paceMax': paceMax,
      'frames': stats.frames,
      'budgetMs': stats.budgetMs,
      'overBudgetFrames': stats.overBudgetFrames,
      'severeFrames': stats.severeFrames,
      'rasterP50Ms': stats.rasterP50Ms,
      'rasterP99Ms': stats.rasterP99Ms,
      'rasterMaxMs': stats.rasterMaxMs,
      'buildP99Ms': stats.buildP99Ms,
      'buildMaxMs': stats.buildMaxMs,
    },
  };
  debugPrint('[paced_bake] $name ${binding.reportData![name]}');

  expect(complete, isTrue, reason: '$name: the bake did not finish in time');
  if (_enforce && pauseRules) {
    expect(
      stats.overBudgetFrames,
      0,
      reason: '$name: frames over the ${budget.toStringAsFixed(1)} ms budget',
    );
  }
}

// ---- host ----------------------------------------------------------------------

/// A panel-like host with cheap content: a spinner, a slide-in sheet and a
/// grid of letters. Reports scrolling and opening through notifiers, the way
/// the real viewport and panel will.
class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  final scrolling = ValueNotifier<bool>(false);
  final opening = ValueNotifier<bool>(false);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  late final AnimationController slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    _spin.dispose();
    slide.dispose();
    scrolling.dispose();
    opening.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification) scrolling.value = true;
    if (n is ScrollEndNotification) scrolling.value = false;
    return false;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: RotationTransition(
                turns: _spin,
                child: const Icon(Icons.refresh, size: 40),
              ),
            ),
          ),
          SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: const Offset(0, 0.3),
            ).animate(CurvedAnimation(parent: slide, curve: Curves.easeOut)),
            child: Material(
              elevation: 8,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                  ),
                  itemCount: 4000,
                  itemBuilder: (context, i) => ColoredBox(
                    color: Colors.primaries[i % Colors.primaries.length]
                        .withValues(alpha: 0.2),
                    child: Center(
                      child: Text(String.fromCharCode(65 + i % 26)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
