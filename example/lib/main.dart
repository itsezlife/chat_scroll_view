import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/boot.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/emoji_glyph_cache.dart';
import 'package:chat_scroll_view_example/src/common/pre_ime_back.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/view/widget_chat_screen.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_chat_theme.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_markdown_theme.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/unread_separator.dart';
import 'package:flutter/material.dart';
import 'package:l/l.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entry point for the widget-based [ChatScrollView] demo.
void main() => l.capture<void>(
  () => runZonedGuarded<void>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      bindExamplePreImeBack();
      await bootApp(
        createServices: _createServices,
        appOf: (services) => ChatDemoApp(services: services),
      );
    },
    (error, stackTrace) =>
        dev.log('Top level exception', error: error, stackTrace: stackTrace),
  ),
  // Every log goes through `print`, so `adb logcat -s flutter`, `flutter run`
  // and `grep` all see it. Verbose levels follow `l`'s defaults.
  const LogOptions(
    handlePrint: true,
    printColors: false,
    output: LogOutput.print,
    outputInRelease: true,
  ),
);

// Backend, stores and the emoji catalogue before the first frame, so the
// panel's last page and the recents are there when it first paints. When one
// of the two fails the other, if it got as far as existing, is freed.
Future<AppServices> _createServices() async {
  final glyphCache = createExampleEmojiGlyphCache();
  final services = AppServices.create(
    glyphCache: glyphCache.cache,
    glyphArtVersion: glyphCache.artVersion,
  );
  // Its own failure is awaited below; until then it is not an unhandled one.
  services.ignore();
  try {
    await Supabase.initialize(
      url: DemoConfig.supabaseUrl,
      publishableKey: DemoConfig.supabasePublishableKey,
    );
  } on Object {
    unawaited(services.then((made) => made.dispose(), onError: (_) {}));
    rethrow;
  }
  return services;
}

/// {@template chat_demo_app}
/// App hosting the chat viewport demo.
///
/// The app owns nothing: [services] are created by the caller (`main`, or a
/// test) and disposed by it.
/// {@endtemplate}
class ChatDemoApp extends StatelessWidget {
  /// {@macro chat_demo_app}
  const ChatDemoApp({
    required this.services,
    this.chatDataSourceLoader,
    this.softKeyboard = const PlatformSoftKeyboard(),
    this.presentationPolicy,
    super.key,
  });

  /// The long-lived services every screen draws on.
  final AppServices services;

  /// Replaces the bundled message source; see
  /// [WidgetChatScreen.dataSourceLoader]. The app leaves this null.
  final ChatDataSourceLoader? chatDataSourceLoader;

  /// The soft keyboard's readings and commands; a test passes a fake.
  final SoftKeyboardPort softKeyboard;

  /// Where the panel appears; null for the policy of the platform.
  final PanelPresentationPolicy? presentationPolicy;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Scroll View',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      extensions: const <ThemeExtension<dynamic>>[UnreadSeparatorColors.dark],
    ),
    builder: (context, child) => AppChrome(
      services: services,
      child: DemoMarkdownTheme(child: DemoChatTheme(child: child!)),
    ),
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: false,
    home: WidgetChatScreen(
      services: services,
      dataSourceLoader: chatDataSourceLoader,
      softKeyboard: softKeyboard,
      presentationPolicy: presentationPolicy,
    ),
  );
}
