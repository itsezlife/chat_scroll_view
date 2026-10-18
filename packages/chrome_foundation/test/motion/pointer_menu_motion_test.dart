import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const motion = ChromeMotion.standard();

  group('pointer menu roles', () {
    test('the menu grows over 200 ms; the curves are per property', () {
      expect(
        motion[MotionRole.pointerMenuShow].duration,
        const Duration(milliseconds: 200),
      );
      expect(motion[MotionRole.pointerMenuShow].curve, Curves.linear);
    });

    test('the menu fades out over 150 ms, linear', () {
      expect(
        motion[MotionRole.pointerMenuHide].duration,
        const Duration(milliseconds: 150),
      );
      expect(motion[MotionRole.pointerMenuHide].curve, Curves.linear);
    });

    test('an instant speed removes both', () {
      const data = ChromeMotionData(speed: ChromeMotionSpeed.instant);
      expect(data.durationOf(MotionRole.pointerMenuShow), Duration.zero);
      expect(data.durationOf(MotionRole.pointerMenuHide), Duration.zero);
    });
  });

  group('EaseOutCirc', () {
    const curve = EaseOutCirc();

    test('runs from 0 to 1', () {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    });

    test('is sqrt(1 - (t - 1)^2)', () {
      expect(curve.transform(0.5), closeTo(math.sqrt(0.75), 1e-12));
      expect(curve.transform(0.25), closeTo(math.sqrt(1 - 0.5625), 1e-12));
    });

    test('rises fast: past 0.74 a third of the way in', () {
      expect(curve.transform(1 / 3), closeTo(0.7454, 1e-3));
    });
  });

  group('PointerMenuTiming', () {
    test('the submenu aim hold is 300 ms', () {
      expect(PointerMenuTiming.aimHold, const Duration(milliseconds: 300));
    });

    test('a ripple grows over 650 ms and fades over 200 ms', () {
      expect(PointerMenuTiming.rippleGrow, const Duration(milliseconds: 650));
      expect(PointerMenuTiming.rippleFade, const Duration(milliseconds: 200));
    });
  });
}
