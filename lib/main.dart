// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:chatscrollview/src/chat_widgets/demo/widget_chat_screen.dart';
import 'package:chatscrollview/src/demo_config.dart';
import 'package:flutter/material.dart';
import 'package:l/l.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entry point for the widget-based [ChatScrollView] demo
/// (`lib/src/chat_widgets/`).
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
