import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/features/chat/view/widget_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:l/l.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entry point for the widget-based [ChatScrollView] demo.
void main() => runZonedGuarded<void>(() async {
  await Supabase.initialize(
    url: DemoConfig.supabaseUrl,
    publishableKey: DemoConfig.supabasePublishableKey,
  );
  runApp(const ChatDemoApp());
}, (error, stackTrace) => l.e('Top level exception: $error'));

/// {@template chat_demo_app}
/// App hosting the chat viewport demo.
/// {@endtemplate}
class ChatDemoApp extends StatelessWidget {
  /// {@macro chat_demo_app}
  const ChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Scroll View',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    ),
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: false,
    home: const WidgetChatScreen(),
  );
}
