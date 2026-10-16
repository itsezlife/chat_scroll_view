import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  group('delivery', () {
    test('calls a registered listener once per notification', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier
        ..addListener(() => calls++)
        ..notify()
        ..notify();
      expect(calls, 2);
    });

    test('calls listeners in registration order', () {
      final notifier = ObservableNotifier();
      final order = <String>[];
      notifier
        ..addListener(() => order.add('a'))
        ..addListener(() => order.add('b'))
        ..notify();
      expect(order, ['a', 'b']);
    });

    test('stops calling a removed listener', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      void listener() => calls++;
      notifier
        ..addListener(listener)
        ..notify()
        ..removeListener(listener)
        ..notify();
      expect(calls, 1);
    });
  });

  group('duplicate registration', () {
    test('calls a listener added twice once per notification', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      void listener() => calls++;
      notifier
        ..addListener(listener)
        ..addListener(listener)
        ..notify();
      expect(calls, 1);
    });

    test('unregisters a twice-added listener with one removal', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      void listener() => calls++;
      notifier
        ..addListener(listener)
        ..addListener(listener)
        ..removeListener(listener)
        ..notify();
      expect(calls, 0);
    });

    test('ignores removing a listener that was never added', () {
      final notifier = ObservableNotifier();
      expect(() => notifier.removeListener(() {}), returnsNormally);
    });
  });

  group('changes made during dispatch', () {
    test('does not call a listener added during the running notification', () {
      final notifier = ObservableNotifier();
      var lateCalls = 0;
      void late() => lateCalls++;
      var first = true;
      notifier
        ..addListener(() {
          if (first) notifier.addListener(late);
          first = false;
        })
        ..notify();
      expect(lateCalls, 0);

      notifier.notify();
      expect(lateCalls, 1);
    });

    test('does not call a listener removed by an earlier listener', () {
      final notifier = ObservableNotifier();
      var victimCalls = 0;
      void victim() => victimCalls++;
      notifier
        ..addListener(() => notifier.removeListener(victim))
        ..addListener(victim)
        ..notify();
      expect(victimCalls, 0);
    });

    test('lets a listener remove itself and keeps the others running', () {
      final notifier = ObservableNotifier();
      final order = <String>[];
      late void Function() once;
      once = () {
        order.add('once');
        notifier.removeListener(once);
      };
      notifier
        ..addListener(once)
        ..addListener(() => order.add('steady'))
        ..notify()
        ..notify();
      expect(order, ['once', 'steady', 'steady']);
    });

    test('calls a listener that was removed and re-added in the same pass', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      void victim() => calls++;
      notifier
        ..addListener(() {
          notifier
            ..removeListener(victim)
            ..addListener(victim);
        })
        ..addListener(victim)
        ..notify();
      expect(calls, 1);
    });
  });

  group('re-entrancy', () {
    test('delivers a notification raised by a listener before it returns', () {
      final notifier = ObservableNotifier();
      final trace = <String>[];
      var nested = false;
      notifier
        ..addListener(() {
          trace.add('first:in');
          if (!nested) {
            nested = true;
            notifier.notify();
          }
          trace.add('first:out');
        })
        ..addListener(() => trace.add('second'));
      notifier.notify();
      expect(trace, [
        'first:in',
        'first:in',
        'first:out',
        'second',
        'first:out',
        'second',
      ]);
    });

    test('lets a nested notification see a listener removed above it', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      void counted() => calls++;
      var nested = false;
      notifier
        ..addListener(() {
          if (nested) return;
          nested = true;
          notifier
            ..removeListener(counted)
            ..notify();
        })
        ..addListener(counted)
        ..notify();
      expect(calls, 0);
    });
  });

  group('after dispose', () {
    test('stays silent for listeners registered before', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier
        ..addListener(() => calls++)
        ..dispose()
        ..notify();
      expect(calls, 0);
      expect(notifier.isDisposed, isTrue);
    });

    test('registers nothing and ignores removal', () {
      final notifier = ObservableNotifier()..dispose();
      var calls = 0;
      void listener() => calls++;
      notifier
        ..addListener(listener)
        ..removeListener(listener)
        ..notify();
      expect(calls, 0);
    });

    test('tolerates a second dispose', () {
      final notifier = ObservableNotifier()..dispose();
      expect(notifier.dispose, returnsNormally);
    });

    test('lets a listener dispose the notifier mid-pass', () {
      final notifier = ObservableNotifier();
      var laterCalls = 0;
      notifier
        ..addListener(notifier.dispose)
        ..addListener(() => laterCalls++)
        ..notify();
      expect(laterCalls, 0);
    });
  });

  group('a throwing listener', () {
    test('does not stop the others and reaches the zone handler', () {
      final errors = <Object>[];
      var laterCalls = 0;
      runZonedGuarded(() {
        ObservableNotifier()
          ..addListener(() => throw StateError('boom'))
          ..addListener(() => laterCalls++)
          ..notify();
      }, (error, _) => errors.add(error));
      expect(laterCalls, 1);
      expect(errors, [isA<StateError>()]);
    });

    test('does not break the code that notified', () {
      final notifier = ObservableNotifier()
        ..addListener(() => throw StateError('boom'));
      var returned = false;
      runZonedGuarded(() {
        notifier.notify();
        returned = true;
      }, (_, _) {});
      expect(returned, isTrue);
    });
  });

  group('batch', () {
    test('notifies once for several notifications inside it', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier
        ..addListener(() => calls++)
        ..batch(() {
          notifier
            ..notify()
            ..notify()
            ..notify();
        });
      expect(calls, 1);
    });

    test('delivers nothing while the mutation is still running', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier.addListener(() => calls++);
      notifier.batch(() {
        notifier.notify();
        expect(calls, 0);
      });
      expect(calls, 1);
    });

    test('stays silent when nothing was reported', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier
        ..addListener(() => calls++)
        ..batch(() {});
      expect(calls, 0);
    });

    test('merges nested batches into the outermost one', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier.addListener(() => calls++);
      notifier.batch(() {
        notifier
          ..batch(notifier.notify)
          ..notify();
        expect(calls, 0);
      });
      expect(calls, 1);
    });

    test('still notifies, then rethrows, when the mutation throws', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier.addListener(() => calls++);
      expect(
        () => notifier.batch(() {
          notifier.notify();
          throw StateError('half done');
        }),
        throwsStateError,
      );
      expect(calls, 1);
    });

    test('notifies normally again once the batch is over', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier
        ..addListener(() => calls++)
        ..batch(notifier.notify)
        ..notify();
      expect(calls, 2);
    });

    test('drops the pending notification when disposed mid-batch', () {
      final notifier = ObservableNotifier();
      var calls = 0;
      notifier.addListener(() => calls++);
      notifier.batch(() {
        notifier
          ..notify()
          ..dispose();
      });
      expect(calls, 0);
    });
  });
}
