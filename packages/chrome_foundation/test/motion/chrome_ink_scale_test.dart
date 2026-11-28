import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget target(
    ChromeInkScale? scale, {
    double width = 200,
    ChromeInkKind kind = ChromeInkKind.ripple,
    ChromeMotionSpeed? speed,
  }) {
    Widget ink = Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ChromeInk(
          kind: kind,
          color: const Color(0xFF000000),
          scale: scale,
          onTap: () {},
          child: SizedBox(width: width, height: 40),
        ),
      ),
    );
    if (speed != null) {
      ink = ChromeMotionScope(speed: speed, child: ink);
    }
    return ink;
  }

  double scaleOf(WidgetTester tester) {
    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(ChromeInk),
        matching: find.byType(Transform),
      ),
    );
    if (transforms.isEmpty) return 1;
    return transforms.first.transform.storage[0];
  }

  Future<TestGesture> press(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    return gesture;
  }

  testWidgets('a bounce goes to its factor over the press duration', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkBounce.card));
    expect(scaleOf(tester), 1);
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 60));
    final mid = scaleOf(tester);
    expect(mid, lessThan(1));
    expect(mid, greaterThan(0.99));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scaleOf(tester), closeTo(0.99, 1e-9));
    await gesture.up();
  });

  testWidgets('a bounce released overshoots 1 and settles on it over 700 ms', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkBounce.card));
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump();
    var peak = 0.0;
    var below = false;
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final s = scaleOf(tester);
      if (s > peak) peak = s;
      if (peak > 1 && s < peak) below = true;
    }
    expect(peak, greaterThan(1), reason: 'passes the rest value');
    expect(below, isTrue, reason: 'then returns to it');
    expect(scaleOf(tester), closeTo(1, 1e-9));
  });

  testWidgets('the button preset presses over 60 ms to 0.98', (tester) async {
    await tester.pumpWidget(target(ChromeInkBounce.button));
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(scaleOf(tester), closeTo(0.98, 1e-9));
    await gesture.up();
  });

  testWidgets('an inset scale is (w - inset) / w of the laid-out width', (
    tester,
  ) async {
    await tester.pumpWidget(
      target(ChromeInkInset.card, kind: ChromeInkKind.highlight),
    );
    var gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(scaleOf(tester), closeTo(195 / 200, 1e-9));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(tester), closeTo(1, 1e-9));

    await tester.pumpWidget(
      target(ChromeInkInset.button, width: 100, kind: ChromeInkKind.highlight),
    );
    gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 150));
    expect(scaleOf(tester), closeTo(0.9, 1e-9));
    await gesture.up();
  });

  testWidgets('an inset scale is halfway at half its release time, in and '
      'out', (tester) async {
    await tester.pumpWidget(
      target(ChromeInkInset.card, kind: ChromeInkKind.highlight),
    );
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 150));
    // Ease in-out is symmetric: half the way at half the time.
    expect(scaleOf(tester), closeTo(1 - 0.025 / 2, 1e-3));
    await gesture.up();
  });

  testWidgets('a cancelled press returns as a release does', (tester) async {
    await tester.pumpWidget(target(ChromeInkBounce.card));
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester), closeTo(0.99, 1e-9));
    await gesture.cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(scaleOf(tester), closeTo(1, 1e-9));
  });

  testWidgets('a press dragged off the target returns', (tester) async {
    await tester.pumpWidget(target(ChromeInkBounce.card));
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(scaleOf(tester), closeTo(1, 1e-9));
  });

  testWidgets('reduce motion removes the scale', (tester) async {
    await tester.pumpWidget(
      target(ChromeInkBounce.card, speed: ChromeMotionSpeed.instant),
    );
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester), 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 700));
    expect(scaleOf(tester), 1);
  });

  testWidgets('without a scale nothing is transformed', (tester) async {
    await tester.pumpWidget(target(null));
    final gesture = await press(tester);
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.descendant(
        of: find.byType(ChromeInk),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await gesture.up();
  });
}
