import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

double _accelerateDecelerate(double t) => math.cos((t + 1) * math.pi) / 2 + 0.5;

void main() {
  const motion = ChromeMotionData.standard;

  group('the motion for a platform', () {
    test('is the grow on a desktop, the unfold on Android and the spring on '
        'iOS', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(AppearMotion.forPlatform(platform), const AppearMotion.grow());
      }
      expect(
        AppearMotion.forPlatform(TargetPlatform.android),
        const AppearMotion.unfold(),
      );
      expect(
        AppearMotion.forPlatform(TargetPlatform.fuchsia),
        const AppearMotion.unfold(),
      );
      expect(
        AppearMotion.forPlatform(TargetPlatform.iOS),
        const AppearMotion.spring(),
      );
    });
  });

  group('the grow', () {
    const grow = AppearMotion.grow();

    test('takes the pointer menu roles: 200 ms in, 150 ms out', () {
      expect(grow.showDuration(motion), const Duration(milliseconds: 200));
      expect(grow.hideDuration(motion), const Duration(milliseconds: 150));
    });

    test('shows as a pointer menu does: from half the width and 30% of the '
        'height, through its strip', () {
      final start = grow.showAt(0);
      expect(start.widthFraction, 0.5);
      expect(start.heightFraction, 0.3);
      expect(start.opacity, 0);
      expect(start.revealed, 0);
      final half = grow.showAt(0.45);
      final reveal = PointerMenuReveal.at(0.45);
      expect(half.heightFraction, reveal.heightFraction);
      expect(half.widthFraction, reveal.widthFraction);
      expect(half.revealed, reveal.contentRevealed);
      expect(grow.showAt(1), AppearFrame.rest);
    });

    test('leaves by a linear fade at full size', () {
      final frame = grow.hideAt(0.25);
      expect(frame.opacity, 0.75);
      expect(frame.widthFraction, 1);
      expect(frame.heightFraction, 1);
      expect(frame.scale, 1);
    });
  });

  group('the unfold', () {
    const unfold = AppearMotion.unfold();

    test('takes 150 ms and 16 more for each row', () {
      expect(unfold.showDuration(motion), const Duration(milliseconds: 150));
      expect(
        unfold.showDuration(motion, rows: 4),
        const Duration(milliseconds: 214),
      );
      expect(unfold.hideDuration(motion), const Duration(milliseconds: 150));
    });

    test('opens its height from the anchored edge and fades in, '
        'accelerating then decelerating', () {
      final frame = unfold.showAt(0.25);
      expect(frame.widthFraction, 1);
      expect(frame.heightFraction, closeTo(_accelerateDecelerate(0.25), 1e-9));
      expect(frame.opacity, closeTo(_accelerateDecelerate(0.25), 1e-9));
      expect(unfold.showAt(0).heightFraction, 0);
      expect(unfold.showAt(1), AppearFrame.rest);
    });

    test('leaves by drifting 5 toward its anchor and fading', () {
      final end = unfold.hideAt(1);
      expect(end.opacity, 0);
      expect(end.drift, 5);
      final half = unfold.hideAt(0.5);
      expect(half.opacity, closeTo(0.5, 1e-9));
      expect(half.drift, closeTo(2.5, 1e-9));
    });
  });

  group('the spring', () {
    const spring = AppearMotion.spring();

    test('takes 420 ms in and 200 ms out', () {
      expect(spring.showDuration(motion), const Duration(milliseconds: 420));
      expect(spring.hideDuration(motion), const Duration(milliseconds: 200));
    });

    test('scales up from 0.01 without passing full size, and is opaque '
        'after its first 50 ms', () {
      expect(spring.showAt(0).scale, closeTo(0.01, 1e-9));
      expect(spring.showAt(0).opacity, 0);
      expect(spring.showAt(50 / 420).opacity, 1);
      var last = 0.0;
      for (var i = 1; i < 100; i++) {
        final scale = spring.showAt(i / 100).scale;
        expect(scale, greaterThan(last));
        expect(scale, lessThan(1));
        last = scale;
      }
      expect(spring.showAt(1), AppearFrame.rest);
    });

    test('leaves by shrinking back to 0.01 and fading', () {
      final end = spring.hideAt(1);
      expect(end.scale, closeTo(0.01, 1e-9));
      expect(end.opacity, 0);
      expect(spring.hideAt(0.5).opacity, closeTo(0.5, 1e-9));
    });
  });

  test('a speed reaches every duration', () {
    const instant = ChromeMotionData(speed: ChromeMotionSpeed.instant);
    for (final appear in const [
      AppearMotion.grow(),
      AppearMotion.unfold(),
      AppearMotion.spring(),
    ]) {
      expect(appear.showDuration(instant, rows: 3), Duration.zero);
      expect(appear.hideDuration(instant), Duration.zero);
    }
  });

  group('ChromeAppear', () {
    Widget host({required bool visible, VoidCallback? onHidden}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ChromeAppear(
              visible: visible,
              motion: const AppearMotion.unfold(),
              onHidden: onHidden,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        );

    double opacityOf(WidgetTester tester) => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byType(ChromeAppear),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;

    testWidgets('comes in over its show and rests', (tester) async {
      await tester.pumpWidget(host(visible: true));
      expect(opacityOf(tester), 0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(opacityOf(tester), closeTo(0.5, 0.01));
      await tester.pump(const Duration(milliseconds: 80));
      expect(opacityOf(tester), 1);
    });

    testWidgets('goes out over its hide, then says it is hidden', (
      tester,
    ) async {
      var hidden = 0;
      await tester.pumpWidget(host(visible: true));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pumpWidget(host(visible: false, onHidden: () => hidden++));
      await tester.pump(const Duration(milliseconds: 75));
      expect(opacityOf(tester), closeTo(0.5, 0.01));
      expect(hidden, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(hidden, 1);
    });

    testWidgets('under an instant speed shows and hides at once', (
      tester,
    ) async {
      var hidden = 0;
      Widget instant({required bool visible}) => ChromeMotionScope(
        speed: ChromeMotionSpeed.instant,
        child: host(visible: visible, onHidden: () => hidden++),
      );
      await tester.pumpWidget(instant(visible: true));
      await tester.pump();
      expect(opacityOf(tester), 1);
      await tester.pumpWidget(instant(visible: false));
      await tester.pump();
      expect(hidden, 1);
    });
  });
}
