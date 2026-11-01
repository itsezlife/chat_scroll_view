import 'package:chat_scroll_view_example/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'panel_perf/report.dart';
import 'panel_perf/scenario_support.dart' show settle;
import 'wallpaper_perf/wallpaper_harness.dart';
import 'wallpaper_perf/wallpaper_measure.dart';

/// On-device wallpaper suite, the app started straight into the chat.
///
/// The real chat (viewport, composer, glass, side controls, panel) over the
/// demo's patterned freeform wallpaper, scopes above the navigator as a
/// product mounts them. Each scenario reports frame timings and the raster
/// work the wallpaper did (pattern rasterizations, gradient rasters), so a slow frame can be put down to its cause.
///
/// Run in `--profile` with `TARGET=integration_test/wallpaper_chat_perf_test.dart
/// tool/run_panel_perf.sh DEVICE LABEL`; one fresh launch per run, since
/// the first scenario times the cold start.
///
/// | Report key               | Asserted | What it isolates                            |
/// | ------------------------ | -------- | ------------------------------------------- |
/// | `wp_chat_cold_start`     | no       | launch to settled chat, first rasters       |
/// | `wp_chat_fling`          | no       | the chat flung over a still wallpaper       |
/// | `wp_shift`               | no       | three one-step gradient shifts              |
/// | `wp_swirl`               | no       | the four-step entrance swirl                |
/// | `wp_spin`                | no       | the loading spin held two seconds, released |
/// | `wp_panel_toggle`        | no       | emoji panel opened and closed over it       |
/// | `wp_resize_drag`         | yes*     | a desktop window dragged smaller, then back |
/// | `wp_rotate_round_trip`   | yes*     | portrait to landscape and back              |
/// | `wp_split_screen`        | yes*     | the window halved in height and restored    |
///
/// *Asserted on the wallpaper's raster work only (no pattern and no gradient
/// raster); their frames are reported.
const _traceTimeline = bool.fromEnvironment('WALLPAPER_PERF_TIMELINE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('wallpaper behind the chat, started in the chat', (tester) async {
    final reports = <ScenarioReport>[];
    Future<void> measure(
      String name,
      Future<void> Function() body, {
      List<WallpaperRule> rules = const [],
    }) async => reports.add(
      await measureWallpaperScenario(
        tester,
        binding,
        name,
        body: body,
        asserted: rules.isNotEmpty,
        rules: rules,
        timeline: _traceTimeline,
      ),
    );

    late final WallpaperHarness app;
    await measure('wp_chat_cold_start', () async {
      app = await WallpaperHarness.start(tester, start: DemoStart.chat);
    });

    await measure('wp_chat_fling', app.flingChat);

    await measure('wp_shift', () async {
      for (var i = 0; i < 3; i++) {
        app.motion.advance();
        await tester.pump(const Duration(milliseconds: 700));
      }
      await settle(tester);
    });

    await measure('wp_swirl', () async {
      app.motion.swirl();
      await tester.pump(const Duration(milliseconds: 2500));
      await settle(tester);
    });

    await measure('wp_spin', () async {
      final hold = app.motion.holdSpin();
      await tester.pump(const Duration(seconds: 2));
      hold.release();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
    });

    await measure('wp_panel_toggle', app.togglePanel);

    final window = app.windowSize;
    await measure('wp_resize_drag', () async {
      // Thirty frames of a window edge dragged to 60 %, then thirty back.
      final steps = [for (var i = 1; i <= 30; i++) 1 - 0.4 * i / 30];
      await app.resizeThrough([
        for (final f in steps) Size(window.width * f, window.height * f),
      ]);
      await app.resizeThrough([
        for (final f in steps.reversed.skip(1))
          Size(window.width * f, window.height * f),
        window,
      ]);
    }, rules: [resizesWithoutRaster]);

    await measure('wp_rotate_round_trip', () async {
      await app.resizeThrough([window.flipped]);
      await app.resizeThrough([window]);
    }, rules: [resizesWithoutRaster]);

    await measure('wp_split_screen', () async {
      await app.resizeThrough([Size(window.width, window.height / 2)]);
      await app.resizeThrough([window]);
    }, rules: [resizesWithoutRaster]);

    await app.dispose();
    publishWallpaperReports(binding, reports);
  });
}
