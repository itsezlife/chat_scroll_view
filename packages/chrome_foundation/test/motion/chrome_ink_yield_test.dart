/// A target that yields its tap shows the press but leaves the tap to a
/// recognizer above it; a press outside `pressableAt` never starts.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required VoidCallback onOuterTap,
    VoidCallback? onInkTap,
    bool yields = true,
    bool Function(Offset)? pressableAt,
    ChromeInkScale? scale = ChromeInkBounce.card,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: GestureDetector(
        onTap: onOuterTap,
        child: ChromeInk(
          kind: ChromeInkKind.ripple,
          color: const Color(0xFF000000),
          scale: scale,
          onTap: onInkTap,
          yieldsTap: yields,
          pressableAt: pressableAt,
          child: const SizedBox(width: 200, height: 40),
        ),
      ),
    ),
  );

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

  testWidgets('a yielding target presses and the tap goes to the parent', (
    tester,
  ) async {
    var outer = 0;
    var ink = 0;
    await tester.pumpWidget(
      host(onOuterTap: () => outer++, onInkTap: () => ink++),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester), closeTo(0.99, 1e-9));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(outer, 1);
    expect(ink, 0);
    expect(scaleOf(tester), closeTo(1, 1e-9));
  });

  testWidgets('without yielding the target wins the tap', (tester) async {
    var outer = 0;
    var ink = 0;
    await tester.pumpWidget(
      host(onOuterTap: () => outer++, onInkTap: () => ink++, yields: false),
    );
    await tester.tap(find.byType(ChromeInk));
    await tester.pumpAndSettle();
    expect(ink, 1);
    expect(outer, 0);
  });

  testWidgets('a yielding target presses with no onTap', (tester) async {
    var outer = 0;
    await tester.pumpWidget(host(onOuterTap: () => outer++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester), lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(outer, 1);
  });

  testWidgets('a press outside pressableAt does not start', (tester) async {
    var outer = 0;
    await tester.pumpWidget(
      host(onOuterTap: () => outer++, pressableAt: (local) => local.dx > 100),
    );
    final left =
        tester.getTopLeft(find.byType(ChromeInk)) + const Offset(20, 20);
    final gesture = await tester.startGesture(left);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(outer, 1);
  });

  testWidgets('a pointer that leaves for a drag cancels the press', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RawGestureDetector(
            gestures: {
              PanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                    PanGestureRecognizer.new,
                    (r) => r.onUpdate = (_) {},
                  ),
            },
            child: const ChromeInk(
              kind: ChromeInkKind.ripple,
              color: Color(0xFF000000),
              scale: ChromeInkBounce.card,
              onTap: null,
              yieldsTap: true,
              child: SizedBox(width: 200, height: 40),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester), lessThan(1));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), closeTo(1, 1e-9));
    await gesture.up();
  });
}
