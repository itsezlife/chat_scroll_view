import 'package:chatscrollview/src/chat_scroll/chat_extent_animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExtentSpring', () {
    test('retarget preserves velocity continuity', () {
      final spring = ExtentSpring.start(from: 0, to: 100, velocity: 0);
      for (var i = 0; i < 3; i++) {
        spring.advance(1 / 60);
      }
      final velocityBeforeRetarget = spring.velocity;
      spring.retarget(200);
      expect(spring.velocity, closeTo(velocityBeforeRetarget, 5000));
    });

    test('settles at target height', () {
      final spring = ExtentSpring.start(from: 0, to: 60, velocity: 0);
      var steps = 0;
      while (!spring.isDone && steps < 240) {
        spring.advance(1 / 60);
        steps++;
      }
      expect(spring.isDone, isTrue);
      expect(spring.value, closeTo(60, 0.5));
    });
  });

  group('CurveRun', () {
    test('completes at duration', () {
      final run = CurveRun(
        telegramCurve,
        const Duration(milliseconds: 180),
        0,
        1,
      );
      var done = false;
      for (var i = 0; i < 20 && !done; i++) {
        done = run.advance(16);
      }
      expect(done, isTrue);
      expect(run.value, closeTo(1, 0.01));
    });

    test('telegramCurve endpoints', () {
      expect(telegramCurve.transform(0), closeTo(0, 0.001));
      expect(telegramCurve.transform(1), closeTo(1, 0.001));
    });

    test('ignores negative dt', () {
      final run = CurveRun(
        telegramCurve,
        const Duration(milliseconds: 180),
        0,
        1,
      );
      run.advance(-100);
      expect(run.elapsedMs, 0);
      expect(run.value, 0);
      run.advance(90);
      expect(run.value, greaterThan(0));
    });
  });
}
