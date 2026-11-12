import 'package:flutter_test/flutter_test.dart';
import 'package:swipe_pager/swipe_pager.dart';

void main() {
  const physics = SwipePagerPhysics();

  group('a release from a drag that started at rest', () {
    // Velocities in logical px/s at a device pixel ratio of 3: the commit
    // thresholds are 3500 physical px/s, so 1166.7 logical px/s here.
    bool commits(double fraction, double velocity, [double cross = 0]) =>
        physics.commits(
          fraction: fraction,
          velocity: velocity,
          crossVelocity: cross,
          caught: false,
          devicePixelRatio: 3,
        );

    test('stays below a third of the page without a fling', () {
      expect(commits(0.3, 0), isFalse);
      expect(commits(0.3, 1100), isFalse);
    });

    test('commits from a third of the page', () {
      expect(commits(1 / 3, 0), isTrue);
      expect(commits(0.6, 0), isTrue);
    });

    test('commits a short drag on a fling of 3500 physical px/s', () {
      expect(commits(0.05, 1170), isTrue);
      expect(commits(0.05, -1170), isTrue);
    });

    test('does not commit a fling that is more vertical than horizontal', () {
      expect(commits(0.05, 1200, 1300), isFalse);
    });
  });

  group('a release from a drag that caught a settle', () {
    bool commits(double fraction, double velocity) => physics.commits(
      fraction: fraction,
      velocity: velocity,
      crossVelocity: 0,
      caught: true,
      devicePixelRatio: 2,
    );

    test('goes the way of a fling over 1500 physical px/s', () {
      expect(commits(0.2, 760), isTrue);
      expect(commits(0.8, -760), isFalse);
    });

    test('otherwise goes to the nearer page', () {
      expect(commits(0.49, 700), isFalse);
      expect(commits(0.51, -700), isTrue);
    });
  });

  group('a fling under the slop', () {
    bool starts(double velocity, double cross) => physics.startsFling(
      velocity: velocity,
      crossVelocity: cross,
      devicePixelRatio: 3,
    );

    test('starts a swipe from 3000 physical px/s', () {
      expect(starts(1000, 0), isTrue);
      expect(starts(-1000, 0), isTrue);
      expect(starts(990, 0), isFalse);
    });

    test('not when it is more vertical', () {
      expect(starts(1100, 1200), isFalse);
    });
  });

  group('the settle duration', () {
    test('without velocity: 100 ms plus 100 ms per page left', () {
      expect(
        physics.settleDuration(remaining: 0, extent: 400, velocity: 0),
        const Duration(milliseconds: 150),
      );
      expect(
        physics.settleDuration(remaining: 200, extent: 400, velocity: 0),
        const Duration(milliseconds: 150),
      );
      expect(
        physics.settleDuration(remaining: 400, extent: 400, velocity: 0),
        const Duration(milliseconds: 200),
      );
    });

    test('with velocity: four times the time to cover the snap distance', () {
      // remaining 200 of 400: ratio 0.5, sin(0) = 0, distance 200;
      // 4 * 1000 * 200 / 2000 = 400 ms.
      expect(
        physics.settleDuration(remaining: 200, extent: 400, velocity: 2000),
        const Duration(milliseconds: 400),
      );
    });

    test('clamped to 150..600 ms', () {
      expect(
        physics.settleDuration(remaining: 400, extent: 400, velocity: 100000),
        const Duration(milliseconds: 150),
      );
      expect(
        physics.settleDuration(remaining: 400, extent: 400, velocity: 10),
        const Duration(milliseconds: 600),
      );
    });
  });

  test('the settle curve is the quintic ease out', () {
    expect(physics.settleCurve.transform(0), 0);
    expect(physics.settleCurve.transform(0.5), closeTo(1 - 1 / 32, 1e-9));
    expect(physics.settleCurve.transform(1), 1);
  });
}
