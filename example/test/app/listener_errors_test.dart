/// How the host reports what `package:listen` cannot: the library never sets
/// `Listenable.onError`, whose default rethrows and so aborts a notification
/// at the first listener that throws.
library;

import 'package:chat_scroll_view_example/src/app/boot.dart';
import 'package:chat_scroll_view_example/src/app/listener_errors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;

void main() {
  late listen.ErrorCallback previousOnError;
  late FlutterExceptionHandler? previousFlutterOnError;
  final reported = <FlutterErrorDetails>[];

  setUp(() {
    previousOnError = listen.Listenable.onError;
    previousFlutterOnError = FlutterError.onError;
    reported.clear();
    FlutterError.onError = reported.add;
  });
  tearDown(() {
    listen.Listenable.onError = previousOnError;
    FlutterError.onError = previousFlutterOnError;
  });

  test('without the host handler a throwing listener aborts the pass', () {
    final notifier = listen.ValueNotifier<int>(0);
    var reached = false;
    notifier
      ..addListener(() => throw StateError('boom'))
      ..addListener(() => reached = true);

    expect(() => notifier.value = 1, throwsStateError);
    expect(reached, isFalse);
  });

  test('a throwing listener is reported and the others still run', () {
    reportListenerErrors();
    final notifier = listen.ValueNotifier<int>(0);
    var reached = false;
    notifier
      ..addListener(() => throw StateError('boom'))
      ..addListener(() => reached = true);

    notifier.value = 1;

    expect(reached, isTrue);
    expect(reported, hasLength(1));
    expect(reported.single.exception, isStateError);
    expect(reported.single.library, 'package:listen');
  });

  test('a misuse assertion is reported too, not rethrown', () {
    reportListenerErrors();
    final notifier = listen.ChangeNotifier()..dispose();

    notifier.addListener(() {});

    expect(reported, hasLength(1));
    expect(reported.single.exception, isStateError);
  });

  testWidgets('booting the app installs it', (tester) async {
    await bootApp(
      createServices: () async => throw StateError('no catalogue'),
      appOf: (_) => throw StateError('not built'),
      run: (_) {},
    );

    expect(listen.Listenable.onError, isNot(same(previousOnError)));
  });
}
