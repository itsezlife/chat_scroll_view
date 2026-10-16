import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  group('publishing', () {
    test('hands each event to listeners in registration order', () {
      final notifier = EventNotifier<int>();
      final seen = <String>[];
      notifier
        ..addListener((event) => seen.add('a$event'))
        ..addListener((event) => seen.add('b$event'))
        ..publish(1)
        ..publish(2);
      expect(seen, ['a1', 'b1', 'a2', 'b2']);
    });

    test('delivers equal events every time', () {
      final notifier = EventNotifier<int>();
      var calls = 0;
      notifier
        ..addListener((_) => calls++)
        ..publish(7)
        ..publish(7);
      expect(calls, 2);
    });

    test('delivers an event raised by a listener before returning', () {
      final notifier = EventNotifier<int>();
      final seen = <int>[];
      notifier
        ..addListener((event) {
          seen.add(event);
          if (event == 1) notifier.publish(2);
        })
        ..addListener((event) => seen.add(event * 10))
        ..publish(1);
      expect(seen, [1, 2, 20, 10]);
    });
  });

  group('listener contract', () {
    test('ignores a duplicate registration', () {
      final notifier = EventNotifier<int>();
      var calls = 0;
      void listener(int _) => calls++;
      notifier
        ..addListener(listener)
        ..addListener(listener)
        ..publish(1);
      expect(calls, 1);
    });

    test('skips a listener removed during the pass', () {
      final notifier = EventNotifier<int>();
      var calls = 0;
      void victim(int _) => calls++;
      notifier
        ..addListener((_) => notifier.removeListener(victim))
        ..addListener(victim)
        ..publish(1);
      expect(calls, 0);
    });

    test('reports a throwing listener to the zone and carries on', () {
      final errors = <Object>[];
      var calls = 0;
      runZonedGuarded(() {
        EventNotifier<int>()
          ..addListener((_) => throw StateError('boom'))
          ..addListener((_) => calls++)
          ..publish(1);
      }, (error, _) => errors.add(error));
      expect(calls, 1);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('after dispose', () {
    test('delivers nothing and accepts no listeners', () {
      final notifier = EventNotifier<int>();
      var calls = 0;
      notifier
        ..addListener((_) => calls++)
        ..dispose()
        ..addListener((_) => calls++)
        ..publish(1);
      expect(calls, 0);
      expect(notifier.isDisposed, isTrue);
    });
  });
}
