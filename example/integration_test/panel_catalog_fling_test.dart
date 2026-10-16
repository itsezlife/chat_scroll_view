import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'panel_perf/acceptance.dart';
import 'panel_perf/panel_harness.dart';
import 'panel_perf/report.dart';
import 'panel_perf/scenario_support.dart';

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
    final harness = await PanelHarness.start(tester);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    reports.add(
      await measureScenario(
        tester,
        binding,
        kPanelOpenScenario,
        asserted: true,
        body: () async {
          harness.open();
          await tester.pump();
          await settle(tester);
          // As a user's first fling comes a moment after the panel appears.
          await tester.pump(const Duration(milliseconds: 800));
          return null;
        },
      ),
    );

    reports.add(
      await measureScenario(
        tester,
        binding,
        kColdFirstPassScenario,
        asserted: true,
        timeline: _traceTimeline,
        requireBaked: true,
        body: () => flingPass(tester),
      ),
    );

    reports.add(
      await measureScenario(
        tester,
        binding,
        'warm_pass2',
        asserted: false,
        body: () => flingPass(tester),
      ),
    );

    harness.dispose();

    // Close and reopen: a new render object starts with an empty paragraph
    // cache while the engine's glyph atlas stays warm. Isolates the cost the
    // panel pays on every open, separate from first sight of a glyph.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    final reopened = await PanelHarness.start(tester);
    reopened.open();
    await tester.pump();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
    reports.add(
      await measureScenario(
        tester,
        binding,
        'reopen_pass4',
        asserted: false,
        body: () => flingPass(tester),
      ),
    );
    reopened.dispose();

    publishAndAssert(binding, reports);
  });
}
