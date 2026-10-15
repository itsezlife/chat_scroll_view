import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_backend_error.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emoji_page_test.dart' show createTestEmojiDataSource;

/// The chat screen runs from a generated, backend-free message source.
///
/// The acceptance scenario for the panel over the real chat screen
/// (`integration_test/panel_over_chat_test.dart`) depends on this: it has no
/// backend and no bundled comments asset to lean on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyboardPanelStore store;
  late DefaultEmojiDataSource emoji;
  late GeneratedChatDataSource source;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardPanelStore(defaultHeight: 280);
    await store.load();
    emoji = await createTestEmojiDataSource();
    source = GeneratedChatDataSource(messageCount: 200);
  });

  tearDown(() => emoji.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ChatDemoApp(
        keyboardPanelStore: store,
        emojiDataSource: emoji,
        chatDataSourceLoader: () async => source,
      ),
    );
    // Open position resolves over a few async hops, then the first layout.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shows the generated messages without a backend', (tester) async {
    await pumpApp(tester);

    expect(find.byType(DemoBackendError), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ChatScrollView), findsOneWidget);
    expect(find.byType(DemoMessageBubble), findsWidgets);
  });

  testWidgets('the composer emoji button opens the catalogue panel', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(PanelCatalogViewport), findsNothing);

    await tester.tap(find.byType(ChatEnterIconButton).first);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(PanelCatalogViewport), findsOneWidget);
  });
}
