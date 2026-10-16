import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeMotion.standard', () {
    const motion = ChromeMotion.standard();

    test('list transition is 250 ms on the Android list cubic', () {
      final spec = motion[MotionRole.listTransition];
      expect(spec.duration, const Duration(milliseconds: 250));
      expect(spec.curve, ChromeMotion.androidListCurve);
    });

    test('the Android list cubic keeps its measured control points', () {
      expect(
        ChromeMotion.androidListCurve,
        const Cubic(
          0.19919472913616398,
          0.010644531250000006,
          0.27920937042459737,
          0.91025390625,
        ),
      );
    });

    test('every role has a spec and no role is instant at speed 1', () {
      for (final role in MotionRole.values) {
        expect(
          motion[role].duration,
          greaterThan(Duration.zero),
          reason: '$role',
        );
      }
    });

    test('the loop role is one turn of a progress ring: 900 ms, linear', () {
      final spec = motion[MotionRole.loop];
      expect(spec.duration, const Duration(milliseconds: 900));
      expect(spec.curve, Curves.linear);
    });

    test('release overshoots and press does not', () {
      expect(motion[MotionRole.release].curve, isA<OvershootCurve>());
      expect(motion[MotionRole.press].curve, Curves.linear);
    });
  });

  group('copyWith', () {
    test('replaces one role and keeps the others', () {
      const base = ChromeMotion.standard();
      const slow = MotionSpec(Duration(seconds: 1), Curves.easeIn);
      final next = base.copyWith(search: slow);
      expect(next[MotionRole.search], slow);
      for (final role in MotionRole.values.where(
        (r) => r != MotionRole.search,
      )) {
        expect(next[role], base[role], reason: '$role');
      }
    });

    test('has value equality', () {
      const spec = MotionSpec(Duration(seconds: 1), Curves.easeIn);
      expect(
        const ChromeMotion.standard().copyWith(fade: spec),
        const ChromeMotion.standard().copyWith(fade: spec),
      );
      expect(
        const ChromeMotion.standard().copyWith(fade: spec),
        isNot(const ChromeMotion.standard()),
      );
    });
  });

  group('MotionSpec', () {
    test('withSpeed scales only the duration', () {
      const spec = MotionSpec(Duration(milliseconds: 200), Curves.easeIn);
      final fast = spec.withSpeed(const ChromeMotionSpeed.times(2));
      expect(fast.duration, const Duration(milliseconds: 100));
      expect(fast.curve, Curves.easeIn);
    });
  });
}
