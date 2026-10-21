import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;

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

    group('with a host error handler that does not rethrow', () {
      final reported = <Object>[];
      late listen.ErrorCallback previous;

      setUp(() {
        reported.clear();
        previous = listen.Listenable.onError;
        listen.Listenable.onError = (error, _, context) {
          expect(context, listen.ErrorContext.listener);
          reported.add(error);
        };
      });
      tearDown(() => listen.Listenable.onError = previous);

      test('a callback that throws does not stop the others', () {
        final token = CancellationToken();
        var reached = false;
        token
          ..onCancel(() => throw StateError('listener bug'))
          ..onCancel(() => reached = true);

        token.cancel();

        expect(reached, isTrue);
        expect(token.isCancelled, isTrue);
        expect(reported.single, isStateError);
      });

      test('a callback added after cancellation that throws is reported', () {
        final token = CancellationToken()..cancel();

        token.onCancel(() => throw StateError('late listener bug'));

        expect(reported.single, isStateError);
      });
    });
  });
}
