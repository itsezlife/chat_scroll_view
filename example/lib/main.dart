import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_scroll_view/chat_scroll_view.dart' show ChatDataSource;
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/boot.dart';
import 'package:chat_scroll_view_example/src/app/overlay_pause_observer.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/emoji_glyph_cache.dart';
import 'package:chat_scroll_view_example/src/common/environment_specific/host_environment.dart'
    as environment_specific;
import 'package:chat_scroll_view_example/src/common/pre_ime_back.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/comments_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/showcase_bodies.dart';
import 'package:chat_scroll_view_example/src/features/chat/view/widget_chat_screen.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_chat_theme.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_markdown_theme.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/unread_separator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:l/l.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entry point for the widget-based [ChatScrollView] demo.
void main() => l.capture<void>(
  () => runZonedGuarded<void>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // In a browser a right-click opens the browser's own menu over the
      // app's (message menus, the composer's, the panel's) unless the app
      // takes it over.
      if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
      bindExamplePreImeBack();
      await bootApp(
        createServices: _createServices,
        appOf: (services) => ChatDemoApp(
          services: services,
          chatDataSourceLoader: switch (DemoConfig.chatSource) {
            'showcase' => _loadShowcase,
            'comments+showcase' => _loadCommentsWithShowcase,
            _ => null,
          },
        ),
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

// Four rounds of the showcase bodies: custom emoji in the text, spoilers,
// mentions and the emoji-only layouts.
Future<ChatDataSource> _loadShowcase() async => GeneratedChatDataSource(
  messageCount: ShowcaseBodies.all.length * 4,
  style: GeneratedMessageStyle.showcase,
);

// The bundled comments, then one round of the showcase bodies as the newest
// messages.
Future<ChatDataSource> _loadCommentsWithShowcase() =>
    CommentsDataSource.load(tailBodies: ShowcaseBodies.all);

// Backend, stores and the emoji catalogue before the first frame, so the
// panel's last page and the recents are there when it first paints. When one
// of the two fails the other, if it got as far as existing, is freed.
//
// On the web the page's loading widget shows the boot's last steps (the
// page loaded the code up to 90%); it goes with the first frame.
Future<AppServices> _createServices() async {
  environment_specific.$reportBootProgress(92, 'Preparing chats and emoji');
  final glyphCache = createExampleEmojiGlyphCache();
  final services = AppServices.create(
    glyphCache: glyphCache.cache,
    glyphArtVersion: glyphCache.artVersion,
  );
  // Its own failure is awaited below; until then it is not an unhandled one.
  services.ignore();
  try {
    environment_specific.$reportBootProgress(95, 'Connecting');
    await Supabase.initialize(
      url: DemoConfig.supabaseUrl,
      publishableKey: DemoConfig.supabasePublishableKey,
    );
  } on Object {
    unawaited(services.then((made) => made.dispose(), onError: (_) {}));
    rethrow;
  }
  final made = await services;
  environment_specific.$reportBootProgress(100, 'Opening');
  return made;
}

/// {@template chat_demo_app}
/// App hosting the chat viewport demo.
///
/// The app owns nothing: [services] are created by the caller (`main`, or a
/// test) and disposed by it.
/// {@endtemplate}
class ChatDemoApp extends StatefulWidget {
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
  State<ChatDemoApp> createState() => _ChatDemoAppState();
}

class _ChatDemoAppState extends State<ChatDemoApp> {
  // Holds the animations still under every dialog, sheet and page opened over
  // the chat. One per app, so the navigator keeps the same observer across
  // rebuilds.
  late final PlaybackOverlayPauseObserver _overlays =
      PlaybackOverlayPauseObserver(widget.services.activity);

  @override
  void dispose() {
    _overlays.dispose();
    super.dispose();
  }

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
      services: widget.services,
      child: DemoMarkdownTheme(child: DemoChatTheme(child: child!)),
    ),
    navigatorObservers: [_overlays],
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: false,
    home: WidgetChatScreen(
      services: widget.services,
      dataSourceLoader: widget.chatDataSourceLoader,
      softKeyboard: widget.softKeyboard,
      presentationPolicy: widget.presentationPolicy,
    ),
  );
}
