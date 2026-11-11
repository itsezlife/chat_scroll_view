import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:flutter/widgets.dart' show ClampingScrollSimulation;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fling', () {
    test('starts flinging and settles to idle', () {
      final physics = ChatFlingMotion()..startFling(1200);
      expect(physics.isFlinging, isTrue);

      var elapsed = Duration.zero;
      var total = 0.0;
      for (var i = 0; i < 400; i++) {
        elapsed += const Duration(milliseconds: 16);
        total += physics.tickFling(elapsed);
      }
      expect(physics.isFlinging, isFalse);
      expect(total, isNot(0.0));
    });

    test('cancelFling stops immediately', () {
      final physics = ChatFlingMotion()
        ..startFling(800)
        ..cancelFling();
      expect(physics.isFlinging, isFalse);
      expect(physics.tickFling(Duration.zero), 0);
    });
  });

  group('ChatSplineFlingSimulation', () {
    final decelerationRate = math.log(0.78) / math.log(0.9);

    test('lasts the Android OverScroller duration', () {
      // SplineOverScroller.getSplineFlingDuration at 160 logical px per inch.
      const coeff = 0.015 * 9.80665 * 39.37 * 160.0 * 0.84;
      for (final velocity in [800.0, 3000.0, 8000.0]) {
        final l = math.log(0.35 * velocity / coeff);
        final expected = math.exp(l / (decelerationRate - 1));
        final sim = ChatSplineFlingSimulation(velocity: velocity);
        expect(sim.duration, closeTo(expected, 1e-9));
        expect(sim.isDone(sim.duration - 0.001), isFalse);
        expect(sim.isDone(sim.duration), isTrue);
      }
    });

    test('travels as far as ClampingScrollSimulation, over a longer time', () {
      for (final velocity in [800.0, 3000.0, -8000.0]) {
        final sim = ChatSplineFlingSimulation(velocity: velocity);
        final clamping = ClampingScrollSimulation(
          position: 0,
          velocity: velocity,
        );
        expect(sim.x(sim.duration), closeTo(clamping.x(10), 0.5));
        expect(
          sim.duration * decelerationRate * 0.35,
          closeTo(_clampingDuration(clamping), 0.002),
          reason: 'Flutter shortens the Android duration to 0.83 of it',
        );
      }
    });

    test('starts at the fling velocity and eases out monotonically', () {
      final sim = ChatSplineFlingSimulation(velocity: 3000);
      expect(sim.dx(0), closeTo(3000, 3000 * 0.02));
      var last = 0.0;
      for (var t = 0.0; t <= sim.duration; t += 1 / 120) {
        final x = sim.x(t);
        expect(x, greaterThanOrEqualTo(last));
        last = x;
      }
      expect(sim.dx(sim.duration), 0);
    });

    test('a zero velocity is already done', () {
      final sim = ChatSplineFlingSimulation(velocity: 0);
      expect(sim.isDone(0), isTrue);
      expect(sim.x(1), 0);
      expect(sim.dx(0), 0);
    });
  });
}

/// First time [sim] reports done, to 1 ms.
double _clampingDuration(ClampingScrollSimulation sim) {
  var t = 0.0;
  while (!sim.isDone(t)) {
    t += 0.001;
  }
  return t;
}
