import 'dart:async';

import 'package:chatscrollview/src/chat_widgets/demo/widget_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:l/l.dart';

/// Entry point for the widget-based [ChatScrollView] example
/// (`lib/src/chat_widgets/`), the counterpart to the canvas implementation
/// run by `lib/main.dart`.
///
/// Launch via the "main_widgets.dart" configurations in `.vscode/launch.json`,
/// or: `flutter run -t lib/main_widgets.dart`.
void main() => runZonedGuarded<void>(
  () => runApp(const WidgetDemoApp()),
  (error, stackTrace) => l.e('Top level exception: $error'),
);

/// {@template widget_demo_app}
/// App hosting the widget-based chat viewport demo.
/// {@endtemplate}
class WidgetDemoApp extends StatelessWidget {
  /// {@macro widget_demo_app}
  const WidgetDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Scroll View — Widgets',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    ),
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: true,
    home: const WidgetChatScreen(),
  );
}
