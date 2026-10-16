import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:flutter/material.dart';

/// Builds the app's services and runs the app over them, or, when that
/// throws, runs a [BootFailureApp] saying so.
///
/// Without it a failed boot (an unreadable store, a missing asset, a backend
/// that cannot start) leaves the first frame blank with the error only in the
/// log. [createServices] must free what it made when it throws (as
/// `AppServices.create` does); [run] is `runApp` unless a test replaces it.
Future<void> bootApp({
  required Future<AppServices> Function() createServices,
  required Widget Function(AppServices services) appOf,
  void Function(Widget app) run = runApp,
}) async {
  final AppServices services;
  try {
    services = await createServices();
  } on Object catch (error, stackTrace) {
    dev.log('Boot failed', error: error, stackTrace: stackTrace);
    run(BootFailureApp(error: error));
    return;
  }
  run(appOf(services));
}

/// The screen a failed boot shows: that the app could not start, and why.
class BootFailureApp extends StatelessWidget {
  /// The failure screen for [error].
  const BootFailureApp({required this.error, super.key});

  /// What stopped the boot.
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    ),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'The app could not start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
