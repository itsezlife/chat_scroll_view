import 'package:flutter/foundation.dart';

/// Writes every error in full to the log (`adb logcat -s flutter`,
/// `flutter run`), once, at startup.
///
/// Flutter's default dumps only the first error in full; later ones are one
/// line ("Another exception was thrown"), with no stack. Here each framework
/// error is dumped whole, and an error no zone caught (a platform callback's)
/// takes the same road.
void logEveryError() {
  FlutterError.onError = (details) =>
      FlutterError.dumpErrorToConsole(details, forceReport: true);
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    reportTopLevelError(error, stackTrace, context: 'uncaught');
    return true;
  };
}

/// Reports [error], one the app's own code did not catch, through
/// [FlutterError.reportError], so it reaches the log with its stack
/// (`dart:developer`'s `log` reaches only a debugger).
void reportTopLevelError(
  Object error,
  StackTrace stackTrace, {
  String context = 'top level',
}) => FlutterError.reportError(
  FlutterErrorDetails(
    exception: error,
    stack: stackTrace,
    library: 'chat_scroll_view_example',
    context: ErrorDescription('as a $context error'),
  ),
);
