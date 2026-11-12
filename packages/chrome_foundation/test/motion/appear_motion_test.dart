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

  group('the burst', () {
    const burst = AppearMotion.burst();
    const overshoot = OvershootCurve(0.5);

    test('takes 250 ms in and 220 ms out', () {
      expect(burst.showDuration(motion), const Duration(milliseconds: 250));
      expect(burst.hideDuration(motion), const Duration(milliseconds: 220));
    });

    test('opens its frame from the corner while the content fades in and '
        'scales up from half, on one overshooting clock', () {
      final start = burst.showAt(0);
      expect((start.widthFraction, start.heightFraction), (0, 0));
      expect((start.contentOpacity, start.contentScale), (0, 0.5));
      expect(start.opacity, 1);

      final p = overshoot.transform(0.6);
      final mid = burst.showAt(0.6);
      expect(mid.widthFraction, closeTo(p, 1e-9));
      expect(mid.heightFraction, closeTo(p, 1e-9));
      expect(mid.contentOpacity, closeTo(p.clamp(0, 1), 1e-9));
      expect(mid.contentScale, closeTo(0.5 + 0.5 * p, 1e-9));
      // Past full size before it settles.
      expect(burst.showAt(0.85).contentScale, greaterThan(1));
      expect(burst.showAt(1), AppearFrame.rest);
    });

    test('leaves by drifting 5 toward its anchor and fading, accelerating '
        'then decelerating', () {
      final quarter = burst.hideAt(0.25);
      expect(quarter.opacity, closeTo(1 - _accelerateDecelerate(0.25), 1e-9));
      expect(quarter.drift, closeTo(5 * _accelerateDecelerate(0.25), 1e-9));
      expect(burst.hideAt(1).opacity, 0);
      expect(burst.hideAt(1).drift, 5);
    });
  });

  group('the zoom', () {
    const zoom = AppearMotion.zoom();

    test('takes 200 ms in and 220 ms out', () {
      expect(zoom.showDuration(motion), const Duration(milliseconds: 200));
      expect(zoom.hideDuration(motion), const Duration(milliseconds: 220));
    });

    test('fades in over 150 ms while it scales up from 0.95 on an '
        'overshoot', () {
      expect(zoom.showAt(0).opacity, 0);
      expect(zoom.showAt(0).scale, closeTo(0.95, 1e-9));
      expect(
        zoom.showAt(0.375).opacity,
        closeTo(_accelerateDecelerate(0.5), 1e-9),
      );
      expect(zoom.showAt(0.75).opacity, 1);
      expect(
        zoom.showAt(0.5).scale,
        closeTo(0.95 + 0.05 * const OvershootCurve().transform(0.5), 1e-9),
      );
      expect(zoom.showAt(0.8).scale, greaterThan(1));
      expect(zoom.showAt(1), AppearFrame.rest);
    });

    test('leaves over the burst\'s 220 ms, moving 5 away from its anchor', () {
      const burst = AppearMotion.burst();
      for (final t in [0.0, 0.3, 0.7, 1.0]) {
        expect(zoom.hideAt(t).opacity, burst.hideAt(t).opacity);
        expect(zoom.hideAt(t).drift, -burst.hideAt(t).drift);
      }
    });

    test('does not scale its content apart from its surface', () {
      for (final t in [0.0, 0.3, 0.7]) {
        expect(zoom.showAt(t).contentScale, 1);
        expect(zoom.showAt(t).contentOpacity, 1);
      }
    });
  });

  test('a speed reaches every duration', () {
    const instant = ChromeMotionData(speed: ChromeMotionSpeed.instant);
    for (final appear in const [
      AppearMotion.grow(),
      AppearMotion.unfold(),
      AppearMotion.spring(),
      AppearMotion.burst(),
      AppearMotion.zoom(),
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

    testWidgets('an AppearContent inside fades and scales the content over '
        'the surface, about the origin', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ChromeAppear(
              motion: AppearMotion.burst(),
              origin: Alignment.topRight,
              child: ColoredBox(
                color: Color(0xFFFFFFFF),
                child: AppearContent(child: SizedBox(width: 100, height: 60)),
              ),
            ),
          ),
        ),
      );
      Opacity contentOpacity() => tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AppearContent),
          matching: find.byType(Opacity),
        ),
      );
      Transform contentScale() => tester.widget<Transform>(
        find.descendant(
          of: find.byType(AppearContent),
          matching: find.byType(Transform),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final p = const OvershootCurve(0.5).transform(100 / 250);
      expect(contentOpacity().opacity, closeTo(p.clamp(0, 1), 1e-6));
      expect(contentScale().alignment, Alignment.topRight);
      expect(contentScale().transform.storage[0], closeTo(0.5 + 0.5 * p, 1e-6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(contentOpacity().opacity, 1);
      expect(contentScale().transform.storage[0], 1);
    });

    testWidgets('a press on what the surface leaves transparent reaches '
        'what is under it', (tester) async {
      var under = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => under++,
                ),
              ),
              const Center(
                child: ChromeAppear(
                  motion: AppearMotion.unfold(),
                  shadows: [BoxShadow(blurRadius: 4)],
                  child: Padding(
                    padding: EdgeInsets.only(left: 40),
                    child: ColoredBox(
                      color: Color(0xFFFFFFFF),
                      child: SizedBox(width: 100, height: 60),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(
        tester.getTopLeft(find.byType(ChromeAppear)) + const Offset(20, 30),
      );
      expect(under, 1);
    });

    testWidgets('a hide during the show fades from where the surface is', (
      tester,
    ) async {
      var hidden = 0;
      await tester.pumpWidget(host(visible: true));
      await tester.pump(const Duration(milliseconds: 75));
      final before = opacityOf(tester);
      expect(before, closeTo(0.5, 0.01));

      await tester.pumpWidget(host(visible: false, onHidden: () => hidden++));
      // No jump: the next frame is where the show was.
      expect(opacityOf(tester), closeTo(before, 0.02));
      // The show goes on under the fade: each frame follows the last.
      var last = before;
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final now = opacityOf(tester);
        expect((now - last).abs(), lessThan(0.15));
        last = now;
      }
      await tester.pump(const Duration(milliseconds: 20));
      expect(hidden, 1);
      expect(opacityOf(tester), 0);
    });

    testWidgets('a show during the hide turns it back from where it is', (
      tester,
    ) async {
      var hidden = 0;
      await tester.pumpWidget(host(visible: true));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(host(visible: false, onHidden: () => hidden++));
      await tester.pump(const Duration(milliseconds: 75));
      final half = opacityOf(tester);
      expect(half, closeTo(0.5, 0.01));

      await tester.pumpWidget(host(visible: true, onHidden: () => hidden++));
      expect(opacityOf(tester), closeTo(half, 0.02));
      var last = half;
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final now = opacityOf(tester);
        expect(now, greaterThanOrEqualTo(last - 1e-9));
        last = now;
      }
      expect(last, 1);
      expect(hidden, 0);
    });

    test('the composed frame is the show under the hide', () {
      const show = AppearFrame(
        opacity: 0.5,
        widthFraction: 0.6,
        heightFraction: 0.4,
        revealed: 0.3,
      );
      const hide = AppearFrame(opacity: 0.5, drift: 2);
      final frame = AppearFrame.compose(show: show, hide: hide);
      expect(frame.opacity, 0.25);
      expect((frame.widthFraction, frame.heightFraction), (0.6, 0.4));
      expect(frame.revealed, 0.3);
      expect(frame.drift, 2);
      expect(AppearFrame.compose(show: AppearFrame.rest, hide: hide), hide);
      expect(AppearFrame.compose(show: show, hide: AppearFrame.rest), show);
    });

    testWidgets('a grow hidden while it grows keeps growing as it fades', (
      tester,
    ) async {
      final clock = AppearController(vsync: const TestVSync());
      addTearDown(clock.dispose);
      const grow = AppearMotion.grow();
      clock
          .show(
            showDuration: const Duration(milliseconds: 200),
            hideDuration: const Duration(milliseconds: 150),
          )
          .ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final growing = clock.frameOf(grow);
      clock.hide(hideDuration: const Duration(milliseconds: 150)).ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final later = clock.frameOf(grow);
      expect(later.heightFraction, greaterThan(growing.heightFraction));
      expect(later.opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 300));
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
