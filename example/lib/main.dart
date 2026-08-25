import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/pre_ime_back.dart';
import 'package:chat_scroll_view_example/src/features/chat/view/widget_chat_screen.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_chat_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entry point for the widget-based [ChatScrollView] demo.
void main() => runZonedGuarded<void>(
  () async {
    WidgetsFlutterBinding.ensureInitialized();
    bindExamplePreImeBack();

    final keyboardPanelStore = KeyboardPanelStore();
    final emojiDataSource = DefaultEmojiDataSource(
      catalog: LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        categoryTitles: EmojiCategoryTitles.russian,
        stripIconFor: EmojiTabAssets.stripIconForId,
      ),
    );

    // Prefs + emoji catalog before first frame so composer last-tab icon and
    // panel initial page match persist storage (no smile→GIF flash).
    await (
      Supabase.initialize(
        url: DemoConfig.supabaseUrl,
        publishableKey: DemoConfig.supabasePublishableKey,
      ),
      keyboardPanelStore.load(),
      emojiDataSource.load(),
    ).wait;

    runApp(
      ChatDemoApp(
        keyboardPanelStore: keyboardPanelStore,
        emojiDataSource: emojiDataSource,
      ),
    );
  },
  (error, stackTrace) =>
      dev.log('Top level exception', error: error, stackTrace: stackTrace),
);

/// {@template chat_demo_app}
/// App hosting the chat viewport demo.
/// {@endtemplate}
class ChatDemoApp extends StatelessWidget {
  /// {@macro chat_demo_app}
  const ChatDemoApp({
    required this.keyboardPanelStore,
    required this.emojiDataSource,
    super.key,
  });

  /// Preloaded panel height + last type-tab prefs.
  final KeyboardPanelStore keyboardPanelStore;

  /// Preloaded emoji catalog / recents.
  final DefaultEmojiDataSource emojiDataSource;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Scroll View',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    ),
    builder: (context, child) => ChatChromeTheme(
      colors: const ChatChromeColors.dark(),
      child: DemoChatTheme(child: child!),
    ),
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: false,
    home: WidgetChatScreen(
      keyboardPanelStore: keyboardPanelStore,
      emojiDataSource: emojiDataSource,
    ),
  );
}
