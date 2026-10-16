import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OvershootCurve', () {
    test('starts at 0 and ends at 1 for any tension', () {
      for (final tension in [0.0, 1.2, 1.5, 2.0, 5.0]) {
        final curve = OvershootCurve(tension);
        expect(curve.transform(0), closeTo(0, 1e-12), reason: '$tension');
        expect(curve.transform(1), closeTo(1, 1e-12), reason: '$tension');
      }
    });

    test('matches a worked value: tension 2 at the midpoint is 1.125', () {
      expect(const OvershootCurve(2).transform(0.5), closeTo(1.125, 1e-12));
    });

    test('the default tension is the Android interpolator default, 2', () {
      expect(const OvershootCurve().tension, 2);
      expect(const OvershootCurve().transform(0.5), closeTo(1.125, 1e-12));
    });

    test('passes above 1 before settling when tension is positive', () {
      const curve = OvershootCurve(1.5);
      final peak = [
        for (var i = 1; i < 100; i++) curve.transform(i / 100),
      ].reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(1));
    });

    test('more tension overshoots further', () {
      double peak(double tension) => [
        for (var i = 1; i < 100; i++)
          OvershootCurve(tension).transform(i / 100),
      ].reduce((a, b) => a > b ? a : b);
      expect(peak(5), greaterThan(peak(1.5)));
    });
  });
}
