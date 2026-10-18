import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const motion = ChromeMotion.standard();

  group('menu roles', () {
    test('the menu enters in 150 ms, ease out', () {
      expect(
        motion[MotionRole.menuEnter].duration,
        const Duration(milliseconds: 150),
      );
      expect(motion[MotionRole.menuEnter].curve, Curves.easeOut);
    });

    test('the menu leaves in 220 ms, ease in', () {
      expect(
        motion[MotionRole.menuLeave].duration,
        const Duration(milliseconds: 220),
      );
      expect(motion[MotionRole.menuLeave].curve, Curves.easeIn);
    });

    test('a page turns in 300 ms on the CSS ease cubic', () {
      expect(
        motion[MotionRole.menuPage].duration,
        const Duration(milliseconds: 300),
      );
      expect(motion[MotionRole.menuPage].curve, const Cubic(0.25, 0.1, 0.25, 1));
    });

    test('there are exactly three menu roles', () {
      expect(
        MotionRole.values.where((role) => role.name.startsWith('menu')).map(
          (role) => role.name,
        ),
        ['menuEnter', 'menuLeave', 'menuPage'],
      );
    });

    test('an instant speed removes every menu animation', () {
      const data = ChromeMotionData(speed: ChromeMotionSpeed.instant);
      for (final role in [
        MotionRole.menuEnter,
        MotionRole.menuLeave,
        MotionRole.menuPage,
      ]) {
        expect(data.durationOf(role), Duration.zero, reason: '$role');
      }
    });

    test('a faster speed shortens them', () {
      const data = ChromeMotionData(speed: ChromeMotionSpeed.times(2));
      expect(
        data.durationOf(MotionRole.menuPage),
        const Duration(milliseconds: 150),
      );
    });

    test('copyWith replaces a menu role', () {
      final next = motion.copyWith(
        menuLeave: const MotionSpec(Duration(milliseconds: 90), Curves.linear),
      );
      expect(
        next[MotionRole.menuLeave].duration,
        const Duration(milliseconds: 90),
      );
      expect(next[MotionRole.menuEnter], motion[MotionRole.menuEnter]);
    });
  });
}
