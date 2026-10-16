import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancellationToken', () {
    test('starts not cancelled', () {
      expect(CancellationToken().isCancelled, isFalse);
    });

    test('runs its callbacks once when cancelled', () {
      final token = CancellationToken();
      var calls = 0;
      token.onCancel(() => calls++);

      token.cancel();
      token.cancel();

      expect(token.isCancelled, isTrue);
      expect(calls, 1);
    });

    test('runs a callback added after cancellation at once', () {
      final token = CancellationToken()..cancel();
      var calls = 0;

      token.onCancel(() => calls++);

      expect(calls, 1);
    });

    test('a callback that throws does not stop the others', () {
      final token = CancellationToken();
      final uncaught = <Object>[];
      var reached = false;
      token
        ..onCancel(() => throw StateError('listener bug'))
        ..onCancel(() => reached = true);

      runZonedGuarded(token.cancel, (error, _) => uncaught.add(error));

      expect(reached, isTrue);
      expect(token.isCancelled, isTrue);
      expect(uncaught.single, isStateError);
    });
  });
}
