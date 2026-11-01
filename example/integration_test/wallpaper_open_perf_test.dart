import 'package:chat_scroll_view_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'panel_perf/report.dart';
import 'panel_perf/scenario_support.dart' show settle;
import 'wallpaper_perf/wallpaper_harness.dart';
import 'wallpaper_perf/wallpaper_measure.dart';

/// On-device wallpaper suite, the chat opened from the chat list: a row
/// tapped, the chat pushed with the non-opaque slide over the list that keeps
/// painting, as a product opens one.
///
/// Run in `--profile` with `TARGET=integration_test/wallpaper_open_perf_test.dart
/// tool/run_panel_perf.sh DEVICE LABEL`; one fresh launch per run, since
/// the first open is the cold one.
///
/// | Report key                | Asserted | What it isolates                                |
/// | ------------------------- | -------- | ----------------------------------------------- |
/// | `wp_list_start`           | no       | launch to the settled chat list                 |
/// | `wp_open_cold`            | no       | first open of the process                       |
/// | `wp_close`                | no       | the pop back to the list                        |
/// | `wp_reopen_1` … `_3`      | no       | later opens, everything warm                    |
/// | `wp_open_after_shift`     | no       | an open after the gradient moved on             |
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('wallpaper behind a chat opened from the chat list', (
    tester,
  ) async {
    final reports = <ScenarioReport>[];
    Future<void> measure(String name, Future<void> Function() body) async =>
        reports.add(
          await measureWallpaperScenario(tester, binding, name, body: body),
        );

    late final WallpaperHarness app;
    await measure('wp_list_start', () async {
      app = await WallpaperHarness.start(tester, start: DemoStart.chatList);
    });

    await measure('wp_open_cold', app.openChat);
    await measure('wp_close', app.closeChat);

    for (var i = 1; i <= 3; i++) {
      await measure('wp_reopen_$i', () async {
        await app.openChat(index: i);
      });
      await app.closeChat();
    }

    // A step taken while the list is up: the chat opens on a phase it has
    // not shown before.
    app.motion.advance();
    await tester.pump(const Duration(milliseconds: 700));
    await settle(tester);
    await measure('wp_open_after_shift', app.openChat);
    await app.closeChat();

    await app.dispose();
    publishWallpaperReports(binding, reports);
  });
}
