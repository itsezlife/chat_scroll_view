import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const quarterSecond = Duration(milliseconds: 250);

  group('ChromeMotionSpeed', () {
    test('normal leaves a duration unchanged', () {
      expect(ChromeMotionSpeed.normal.scale(quarterSecond), quarterSecond);
    });

    test('times(2) halves, times(0.5) doubles', () {
      expect(
        const ChromeMotionSpeed.times(2).scale(quarterSecond),
        const Duration(milliseconds: 125),
      );
      expect(
        const ChromeMotionSpeed.times(0.5).scale(quarterSecond),
        const Duration(milliseconds: 500),
      );
    });

    test('instant collapses any duration to zero', () {
      expect(ChromeMotionSpeed.instant.scale(quarterSecond), Duration.zero);
      expect(ChromeMotionSpeed.instant.isInstant, isTrue);
      expect(ChromeMotionSpeed.normal.isInstant, isFalse);
    });

    test('rounds to whole microseconds', () {
      expect(
        const ChromeMotionSpeed.times(
          3,
        ).scale(const Duration(microseconds: 10)),
        const Duration(microseconds: 3),
      );
    });

    test('rejects a non-positive or non-finite multiplier', () {
      expect(() => ChromeMotionSpeed.times(0), throwsAssertionError);
      expect(() => ChromeMotionSpeed.times(-1), throwsAssertionError);
      expect(
        () => ChromeMotionSpeed.times(double.infinity),
        throwsAssertionError,
      );
      expect(() => ChromeMotionSpeed.times(double.nan), throwsAssertionError);
    });

    test('has value equality', () {
      expect(
        const ChromeMotionSpeed.times(2),
        const ChromeMotionSpeed.times(2),
      );
      expect(ChromeMotionSpeed.normal, isNot(ChromeMotionSpeed.instant));
      expect(
        const ChromeMotionSpeed.times(2),
        isNot(const ChromeMotionSpeed.times(3)),
      );
    });
  });
}
