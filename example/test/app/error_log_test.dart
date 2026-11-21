/// Every error reaches the log in full: Flutter's default writes only the
/// first one with its stack.
library;

import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:chat_scroll_view_example/src/app/error_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterExceptionHandler? previousOnError;
  late ErrorCallback? previousPlatformOnError;
  late DebugPrintCallback previousPrint;
  final lines = <String>[];

  setUp(() {
    previousOnError = FlutterError.onError;
    previousPlatformOnError = PlatformDispatcher.instance.onError;
    previousPrint = debugPrint;
    lines.clear();
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  });
  tearDown(() {
    FlutterError.onError = previousOnError;
    PlatformDispatcher.instance.onError = previousPlatformOnError;
    debugPrint = previousPrint;
    FlutterError.resetErrorCount();
  });

  StackTrace stackOf(String name) =>
      StackTrace.fromString('#0      $name (package:x/x.dart:1:1)\n');

  test('each framework error is written whole, the second too', () {
    logEveryError();
    for (final name in ['first', 'second']) {
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('$name boom'),
          stack: stackOf(name),
        ),
      );
    }
    final text = lines.join('\n');
    expect(text, contains('first boom'));
    expect(text, contains('second boom'));
    expect(text, contains('#0      second'));
    expect(text, isNot(contains('Another exception was thrown')));
  });

  test('an error no zone caught, and one the app reports at the top, are '
      'written with their stacks', () {
    logEveryError();
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('platform boom'),
        stackOf('platformCallback'),
      ),
      isTrue,
    );
    reportTopLevelError(StateError('zone boom'), stackOf('zoneBody'));
    final text = lines.join('\n');
    expect(text, contains('platform boom'));
    expect(text, contains('#0      platformCallback'));
    expect(text, contains('zone boom'));
    expect(text, contains('#0      zoneBody'));
  });
}
