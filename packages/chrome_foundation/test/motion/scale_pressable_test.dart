import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

double _scaleOf(WidgetTester tester) =>
    tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;

Widget _app({
  required VoidCallback? onPressed,
  ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
  double? releaseTension,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ChromeMotionScope(
    speed: speed,
    child: Center(
      child: ScalePressable(
        onPressed: onPressed,
        releaseTension: releaseTension,
        child: const SizedBox(width: 40, height: 40),
      ),
    ),
  ),
);

void main() {
  testWidgets('rests at scale 1', (tester) async {
    await tester.pumpWidget(_app(onPressed: () {}));
    expect(_scaleOf(tester), 1);
  });

  testWidgets('shrinks by the reduction while pressed', (tester) async {
    await tester.pumpWidget(_app(onPressed: () {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScalePressable)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(_scaleOf(tester), closeTo(0.9, 1e-9));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('release overshoots above 1 then settles on 1', (tester) async {
    await tester.pumpWidget(_app(onPressed: () {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScalePressable)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    var peak = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      peak = peak > _scaleOf(tester) ? peak : _scaleOf(tester);
    }
    await tester.pumpAndSettle();
    expect(peak, greaterThan(1));
    expect(_scaleOf(tester), 1);
  });

  testWidgets('taps reach onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(onPressed: () => taps++));
    await tester.tap(find.byType(ScalePressable));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a null handler neither scales nor fires', (tester) async {
    await tester.pumpWidget(_app(onPressed: null));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScalePressable)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scaleOf(tester), 1);
    await gesture.up();
  });

  testWidgets('instant speed jumps straight to the pressed scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(onPressed: () {}, speed: ChromeMotionSpeed.instant),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScalePressable)),
    );
    await tester.pump();
    expect(_scaleOf(tester), closeTo(0.9, 1e-9));
    await gesture.up();
    await tester.pump();
    expect(_scaleOf(tester), 1);
  });

  testWidgets('release takes the release role duration', (tester) async {
    await tester.pumpWidget(_app(onPressed: () {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScalePressable)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 349));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 2));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
