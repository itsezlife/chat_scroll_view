import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'panel_perf/acceptance.dart';
import 'panel_perf/report.dart';
import 'panel_perf/scenario_support.dart';

/// On-device acceptance test for the emoji keyboard panel over the real chat
/// screen.
///
/// The same bar as the bare-panel test (`panel_catalog_fling_test.dart`): the
/// open animation and the cold first fling over the whole catalogue drop no
/// frame over one vsync budget and keep raster p99 at most 2 ms. What differs
/// is the surroundings: the panel is opened from the composer of the real
/// screen, with the chat viewport, glass composer, fades and side controls
/// behind and around it, so jank from any of them is caught, not only jank from
/// glyphs.
///
/// The chat runs on generated messages ([GeneratedChatDataSource]) through the
/// screen's `dataSourceLoader` seam: no backend, no network, no bundled asset.
///
/// Run three fresh launches of this suite with
/// `dart run tool/panel_perf.dart --suite chat <device-id> <label>`, in
/// `--profile`. Every verdict needs a fresh launch, so this suite never shares
/// a process with the bare one.
///
/// | Report key              | Asserted | What it isolates                       |
/// | ----------------------- | -------- | -------------------------------------- |
/// | `chat_panel_open`       | yes      | open animation over the chat           |
/// | `chat_cold_first_pass`  | yes      | first sight of every glyph, chat behind |
/// | `chat_warm_pass2`       | no       | same pass with every glyph already seen |
///
/// Comparing `chat_warm_pass2` with the bare `warm_pass2` shows what the chat
/// costs after the glyphs stopped mattering; a pass that fails here and passes
/// there is the finding this scenario exists for.
const _traceTimeline = bool.fromEnvironment('PANEL_PERF_TIMELINE');

/// Long enough that no fling can reach an end of the chat.
const _messageCount = 5000;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('panel over the chat screen meets the frame budget', (
    tester,
  ) async {
    final reports = <ScenarioReport>[];

    final app = await _ChatHarness.start(tester);

    reports.add(
      await measureScenario(
        tester,
        binding,
        kChatPanelOpenScenario,
        asserted: true,
        body: () async {
          await app.openPanel();
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
        kChatColdFirstPassScenario,
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
        'chat_warm_pass2',
        asserted: false,
        body: () => flingPass(tester),
      ),
    );

    await app.dispose();
    publishAndAssert(binding, reports);
  });
}

/// The real [ChatDemoApp] on generated messages, started from clean storage.
final class _ChatHarness {
  _ChatHarness._(this._tester, this._services);

  final WidgetTester _tester;
  final AppServices _services;

  static Future<_ChatHarness> start(WidgetTester tester) async {
    // A previous session may have left the panel on another page or a
    // different height; every launch must open the same panel, so the stores
    // start empty.
    final services = await AppServices.create(
      keyValueStore: FakeKeyValueStore(),
    );

    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        chatDataSourceLoader: () async =>
            GeneratedChatDataSource(messageCount: _messageCount),
      ),
    );

    // The chat resolves its open position asynchronously; measuring before
    // the first messages are on screen would time the load, not the panel.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(DemoMessageBubble).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('chat screen showed no message within 30 s');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    return _ChatHarness._(tester, services);
  }

  /// The user's path: tap the composer's panel button.
  Future<void> openPanel() async {
    await _tester.tap(
      find.byKey(const ValueKey<String>(ChatComposerActions.panel)),
    );
    await _tester.pump();
    await settle(_tester);
  }

  /// Unmounts the screen before freeing the services it still listens to.
  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    _services.dispose();
  }
}
