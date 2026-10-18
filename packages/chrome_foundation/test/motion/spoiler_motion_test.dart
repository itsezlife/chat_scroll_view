import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the reveal ripple', () {
    test('is a 300 ms linear role', () {
      final spec = const ChromeMotion.standard()[MotionRole.spoilerReveal];
      expect(spec.duration, const Duration(milliseconds: 300));
      expect(spec.curve, Curves.linear);
    });

    test('is instant under an instant speed', () {
      const data = ChromeMotionData(speed: ChromeMotionSpeed.instant);
      expect(data.durationOf(MotionRole.spoilerReveal), Duration.zero);
    });
  });

  group('SpoilerParticleMotion.standard', () {
    const particles = SpoilerParticleMotion.standard;

    test('speed 4-10 dp/s and life 1-3 s', () {
      expect(particles.minSpeed, 4);
      expect(particles.maxSpeed, 10);
      expect(particles.minLife, const Duration(seconds: 1));
      expect(particles.maxLife, const Duration(seconds: 3));
    });

    test('ticks at 30 frames per second', () {
      expect(particles.framesPerSecond, 30);
      expect(particles.tick, const Duration(microseconds: 33333));
    });

    test(
      'a normal or faster speed keeps the tick, instant makes it static',
      () {
        expect(
          particles.tickAt(ChromeMotionSpeed.normal),
          const Duration(microseconds: 33333),
        );
        expect(
          particles.tickAt(const ChromeMotionSpeed.times(2)),
          const Duration(microseconds: 33333),
        );
        expect(particles.tickAt(ChromeMotionSpeed.instant), isNull);
      },
    );

    test('has value equality', () {
      expect(
        const SpoilerParticleMotion(maxSpeed: 12),
        isNot(SpoilerParticleMotion.standard),
      );
    });
  });
}
