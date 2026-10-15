import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The real [ChatDemoApp] on generated messages, started from clean prefs.
final class _ChatHarness {
  _ChatHarness._(this._tester, this._emoji);

  final WidgetTester _tester;
  final DefaultEmojiDataSource _emoji;

  static Future<_ChatHarness> start(WidgetTester tester) async {
    // A previous session may have left the panel on another tab or a
    // different height; every launch must open the same panel.
    await (await SharedPreferences.getInstance()).clear();

    final store = KeyboardPanelStore();
    final emoji = DefaultEmojiDataSource(
      catalog: LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        categoryTitles: EmojiCategoryTitles.russian,
        stripIconFor: EmojiTabAssets.stripIconForId,
      ),
    );
    await (store.load(), emoji.load()).wait;

    await tester.pumpWidget(
      ChatDemoApp(
        keyboardPanelStore: store,
        emojiDataSource: emoji,
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
    return _ChatHarness._(tester, emoji);
  }

  /// The user's path: tap the composer's emoji button.
  Future<void> openPanel() async {
    await _tester.tap(find.byType(ChatEnterIconButton).first);
    await _tester.pump();
    await settle(_tester);
  }

  /// Unmounts the screen before freeing the emoji data it still listens to.
  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    _emoji.dispose();
  }
}
