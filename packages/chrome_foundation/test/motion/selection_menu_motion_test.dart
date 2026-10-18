import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const motion = ChromeMotion.standard();

  group('menu roles', () {
    test('the whole toolbar enters in 150 ms and leaves in 100 ms', () {
      expect(
        motion[MotionRole.menuEnter].duration,
        const Duration(milliseconds: 150),
      );
      expect(
        motion[MotionRole.menuExit].duration,
        const Duration(milliseconds: 100),
      );
      expect(
        motion[MotionRole.menuEnter].curve,
        isA<AccelerateDecelerateCurve>(),
      );
      expect(
        motion[MotionRole.menuExit].curve,
        isA<AccelerateDecelerateCurve>(),
      );
    });

    test(
      'the overflow morph is 250 ms, width and height on opposite curves',
      () {
        final ease = motion[MotionRole.menuSizeEase];
        final accelerate = motion[MotionRole.menuSizeAccelerate];
        expect(ease.duration, const Duration(milliseconds: 250));
        expect(ease.curve, Curves.fastOutSlowIn);
        expect(accelerate.duration, const Duration(milliseconds: 250));
        expect(accelerate.curve, isA<LogAccelerateCurve>());
      },
    );

    test('the panels fade for 250, 100 and 150 ms', () {
      final mainOut = motion[MotionRole.menuMainFadeOut];
      final mainIn = motion[MotionRole.menuMainFadeIn];
      final overflowOut = motion[MotionRole.menuOverflowFadeOut];
      expect(mainOut.duration, const Duration(milliseconds: 250));
      expect(mainOut.curve, ChromeMotion.linearOutSlowIn);
      expect(mainIn.duration, const Duration(milliseconds: 100));
      expect(mainIn.curve, ChromeMotion.fastOutLinearIn);
      expect(overflowOut.duration, const Duration(milliseconds: 150));
      expect(overflowOut.curve, ChromeMotion.linearOutSlowIn);
    });

    test('the AOSP interpolators keep their control points', () {
      expect(ChromeMotion.linearOutSlowIn, const Cubic(0, 0, 0.2, 1));
      expect(ChromeMotion.fastOutLinearIn, const Cubic(0.4, 0, 1, 1));
    });

    test('an instant speed removes every menu animation', () {
      const data = ChromeMotionData(speed: ChromeMotionSpeed.instant);
      for (final role in [
        MotionRole.menuEnter,
        MotionRole.menuExit,
        MotionRole.menuSizeEase,
        MotionRole.menuSizeAccelerate,
        MotionRole.menuMainFadeOut,
        MotionRole.menuMainFadeIn,
        MotionRole.menuOverflowFadeOut,
      ]) {
        expect(data.durationOf(role), Duration.zero, reason: '$role');
      }
    });

    test('a faster speed shortens them', () {
      const data = ChromeMotionData(speed: ChromeMotionSpeed.times(2));
      expect(
        data.durationOf(MotionRole.menuSizeEase),
        const Duration(milliseconds: 125),
      );
    });
  });

  group('curves', () {
    test('AccelerateDecelerate is 0.5 - cos(pi t) / 2', () {
      const curve = AccelerateDecelerateCurve();
      expect(curve.transform(0), 0);
      expect(curve.transform(0.5), closeTo(0.5, 1e-9));
      expect(curve.transform(1), closeTo(1, 1e-9));
      // Worked value: 0.5 - cos(pi / 4) / 2.
      expect(curve.transform(0.25), closeTo(0.14644660940672627, 1e-9));
    });

    test('LogAccelerate starts slow and reaches 1', () {
      const curve = LogAccelerateCurve();
      expect(curve.transform(0), closeTo(0, 1e-9));
      expect(curve.transform(1), closeTo(1, 1e-9));
      // Worked value: 1 - (1 - 100^-0.5) / 0.99 = 1 - 0.9 / 0.99 = 1 / 11.
      expect(curve.transform(0.5), closeTo(1 / 11, 1e-9));
    });

    test('LogAccelerate never runs ahead of linear', () {
      const curve = LogAccelerateCurve();
      for (var t = 0.0; t <= 1; t += 0.05) {
        expect(curve.transform(t), lessThanOrEqualTo(t + 1e-9));
      }
      expect(math.pow(100, -0.5), closeTo(0.1, 1e-12));
    });
  });

  group('SelectionMenuTiming', () {
    test('policy timings', () {
      expect(
        SelectionMenuTiming.dismissDelay,
        const Duration(milliseconds: 150),
      );
      expect(
        SelectionMenuTiming.movingGrace,
        const Duration(milliseconds: 500),
      );
      expect(
        SelectionMenuTiming.settleDebounce,
        const Duration(milliseconds: 50),
      );
    });

    test('the morph lasts 200 ms under a 150 dp diagonal, 300 ms over 300', () {
      const base = Duration(milliseconds: 250);
      expect(
        SelectionMenuTiming.morphDuration(base, diagonal: 149),
        const Duration(milliseconds: 200),
      );
      expect(
        SelectionMenuTiming.morphDuration(base, diagonal: 150),
        const Duration(milliseconds: 250),
      );
      expect(
        SelectionMenuTiming.morphDuration(base, diagonal: 300),
        const Duration(milliseconds: 250),
      );
      expect(
        SelectionMenuTiming.morphDuration(base, diagonal: 301),
        const Duration(milliseconds: 300),
      );
    });

    test('the morph scales a host-overridden base by the same ratios', () {
      expect(
        SelectionMenuTiming.morphDuration(
          const Duration(milliseconds: 500),
          diagonal: 100,
        ),
        const Duration(milliseconds: 400),
      );
    });
  });
}
