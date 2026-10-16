import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// An [Observable] under test, with the means to make it signal and to end
/// its life.
final class ObservableHarness {
  /// Creates a harness around [observable].
  const ObservableHarness({
    required this.observable,
    required this.signal,
    required this.dispose,
  });

  /// The read side under test, fresh, with no listener.
  final Observable observable;

  /// Makes the owner signal once, as one logical change would.
  final void Function() signal;

  /// Disposes the owner.
  final void Function() dispose;
}

/// Runs the [Observable] listener contract against the harnesses [create]
/// returns, one per test.
void runObservableContract(ObservableHarness Function() create) {
  group('Observable contract', () {
    late ObservableHarness harness;
    late Observable observable;

    setUp(() {
      harness = create();
      observable = harness.observable;
    });

    test('runs a listener for every signal', () {
      var calls = 0;
      observable.addListener(() => calls++);

      harness.signal();
      harness.signal();

      expect(calls, 2);
    });

    test('runs listeners in the order they were added', () {
      final order = <int>[];
      observable
        ..addListener(() => order.add(1))
        ..addListener(() => order.add(2))
        ..addListener(() => order.add(3));

      harness.signal();

      expect(order, [1, 2, 3]);
    });

    test('runs a listener inside the call that signals', () {
      var ran = false;
      observable.addListener(() => ran = true);

      harness.signal();

      expect(ran, isTrue);
    });

    test('registers the same listener once, and one removal ends it', () {
      var calls = 0;
      void listener() => calls++;
      observable
        ..addListener(listener)
        ..addListener(listener);

      harness.signal();
      expect(calls, 1);

      observable.removeListener(listener);
      harness.signal();
      expect(calls, 1);
    });

    test('ignores the removal of a listener that is not registered', () {
      expect(() => observable.removeListener(() {}), returnsNormally);
    });

    test('stops calling a listener once it is removed', () {
      var calls = 0;
      void listener() => calls++;
      observable.addListener(listener);
      harness.signal();

      observable.removeListener(listener);
      harness.signal();

      expect(calls, 1);
    });

    group('during a signal', () {
      test('lets a listener remove itself', () {
        var calls = 0;
        void once() {
          calls++;
          observable.removeListener(once);
        }

        observable.addListener(once);

        harness
          ..signal()
          ..signal();

        expect(calls, 1);
      });

      test(
        'does not call a listener added meanwhile until the next signal',
        () {
          var late = 0;
          void addedMeanwhile() => late++;
          var added = false;
          observable.addListener(() {
            if (added) return;
            added = true;
            observable.addListener(addedMeanwhile);
          });

          harness.signal();
          expect(late, 0);

          harness.signal();
          expect(late, 1);
        },
      );

      test(
        'does not call a listener removed meanwhile, even if not reached yet',
        () {
          var second = 0;
          void other() => second++;
          observable
            ..addListener(() => observable.removeListener(other))
            ..addListener(other);

          harness.signal();

          expect(second, 0);
        },
      );

      test('delivers every signal when a listener causes another', () {
        var calls = 0;
        var nested = false;
        observable.addListener(() {
          calls++;
          if (nested) return;
          nested = true;
          harness.signal();
        });

        harness.signal();

        expect(calls, 2);
      });
    });

    group('a throwing listener', () {
      test('does not stop the others, and its error is reported', () {
        final errors = <Object>[];
        var after = 0;
        observable
          ..addListener(() => throw StateError('listener failed'))
          ..addListener(() => after++);

        runZonedGuarded(harness.signal, (error, _) => errors.add(error));

        expect(after, 1);
        expect(errors, hasLength(1));
        expect(errors.single, isA<StateError>());
      });

      test('does not break the code that signals', () {
        observable.addListener(() => throw StateError('listener failed'));

        expect(
          () => runZonedGuarded(harness.signal, (_, _) {}),
          returnsNormally,
        );
      });
    });

    group('after dispose', () {
      test('delivers nothing', () {
        var calls = 0;
        observable.addListener(() => calls++);

        harness.dispose();
        harness.signal();

        expect(calls, 0);
      });

      test('registers nothing', () {
        harness.dispose();
        var calls = 0;
        observable.addListener(() => calls++);

        harness.signal();

        expect(calls, 0);
      });

      test('ignores removal', () {
        harness.dispose();

        expect(() => observable.removeListener(() {}), returnsNormally);
      });

      test('can be disposed twice', () {
        harness.dispose();

        expect(harness.dispose, returnsNormally);
      });

      test('is safe to dispose from inside a listener', () {
        var after = 0;
        observable
          ..addListener(harness.dispose)
          ..addListener(() => after++);

        harness.signal();

        expect(after, 0);
      });
    });
  });
}
