import 'dart:async';

import 'package:flutter/material.dart';
import 'package:l/l.dart';

void main() => runZonedGuarded<void>(
  () => runApp(const App()),
  (error, stackTrace) => l.e('Top level exception: $error'),
);

/// {@template app}
/// App widget.
/// {@endtemplate}
class App extends StatelessWidget {
  /// {@macro app}
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Scroll View',
    home: Scaffold(
      appBar: AppBar(title: const Text('Chat Scroll View')),
      body: const SafeArea(child: Center(child: Text('Hello World'))),
    ),
  );
}
