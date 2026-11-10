import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _color = Color(0xFF000000);
const _hover = Color(0xFF00FF00);

void main() {
  var taps = 0;

  setUp(() => taps = 0);

  Widget target(ChromeInkKind kind, {bool enabled = true}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: ChromeInk(
        kind: kind,
        color: _color,
        hoverColor: _hover,
        onTap: enabled ? () => taps++ : null,
        child: const SizedBox(width: 100, height: 40),
      ),
    ),
  );

  // The alpha of the feedback colour drawn, or null when none is.
  double? inkAlpha(WidgetTester tester) {
    double? alpha;
    final box = tester.renderObject<RenderBox>(find.byType(ChromeInk));
    final canvas = TestRecordingCanvas();
    final context = TestRecordingPaintingContext(canvas);
    box.paint(context, Offset.zero);
    for (final call in canvas.invocations) {
      final name = call.invocation.memberName;
      if (name != #drawCircle && name != #drawPaint) continue;
      final paint = call.invocation.positionalArguments.last as Paint;
      if (paint.color.g > 0) continue; // the hover fill
      alpha = paint.color.a;
    }
    return alpha;
  }

  double? circleRadius(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(find.byType(ChromeInk));
    final canvas = TestRecordingCanvas();
    box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
    for (final call in canvas.invocations) {
      if (call.invocation.memberName == #drawCircle) {
        return call.invocation.positionalArguments[1] as double;
      }
    }
    return null;
  }

  testWidgets('the platform kinds: a ripple on Android, a highlight on iOS, '
      'the pointer feedback on a desktop', (tester) async {
    expect(
      ChromeInkKind.forPlatform(TargetPlatform.android),
      ChromeInkKind.ripple,
    );
    expect(
      ChromeInkKind.forPlatform(TargetPlatform.iOS),
      ChromeInkKind.highlight,
    );
    expect(
      ChromeInkKind.forPlatform(TargetPlatform.macOS),
      ChromeInkKind.pointer,
    );
    expect(
      ChromeInkKind.forPlatform(TargetPlatform.windows),
      ChromeInkKind.pointer,
    );
  });

  testWidgets('a secondary click neither taps nor draws: the host\'s '
      'context handlers have it', (tester) async {
    await tester.pumpWidget(target(ChromeInkKind.pointer));
    final mouse = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(inkAlpha(tester), isNull);
    await mouse.up();
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('the primary button still taps', (tester) async {
    await tester.pumpWidget(target(ChromeInkKind.pointer));
    final mouse = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a ripple comes in over 75 ms, grows from the touch over 225 ms '
      'and fades over 150 ms after the release', (tester) async {
    await tester.pumpWidget(target(ChromeInkKind.ripple));
    final centre = tester.getCenter(find.byType(ChromeInk));
    final gesture = await tester.startGesture(centre);
    await tester.pump();
    expect(inkAlpha(tester) ?? 0, closeTo(0, 0.01));

    await tester.pump(const Duration(milliseconds: 75));
    expect(inkAlpha(tester), 1);
    final halfway = circleRadius(tester)!;

    await tester.pump(const Duration(milliseconds: 150));
    final full = circleRadius(tester)!;
    expect(halfway, lessThan(full));
    // To the farthest corner of a 100 x 40 box from its centre.
    expect(full, closeTo(const Offset(50, 20).distance, 0.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(inkAlpha(tester), closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 80));
    expect(inkAlpha(tester), isNull);
    expect(taps, 1);
  });

  testWidgets('a highlight shows at once and fades over 300 ms', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkKind.highlight));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    expect(inkAlpha(tester), 1);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(inkAlpha(tester), closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 160));
    expect(inkAlpha(tester), isNull);
  });

  testWidgets('the pointer feedback fills under a hovering mouse', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkKind.pointer));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ChromeInk)));
    await tester.pump();

    expect(
      find.byType(ChromeInk),
      paints..something((method, arguments) {
        if (method != #drawPaint) return false;
        return (arguments.single as Paint).color == _hover;
      }),
    );
  });

  testWidgets('a ripple dragged off its target fades over 150 ms and does '
      'not tap', (tester) async {
    await tester.pumpWidget(target(ChromeInkKind.ripple));
    final box = tester.getRect(find.byType(ChromeInk));
    final gesture = await tester.startGesture(box.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    expect(inkAlpha(tester), 1);

    // Past the touch slop outside the box.
    await gesture.moveTo(box.centerRight + const Offset(40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(inkAlpha(tester), closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 80));
    expect(inkAlpha(tester), isNull);

    // Back over the target: an Android press does not come back.
    await gesture.moveTo(box.center);
    await tester.pump();
    expect(inkAlpha(tester), isNull);
    await gesture.up();
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('a ripple moved within the touch slop of its box stays', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkKind.ripple));
    final box = tester.getRect(find.byType(ChromeInk));
    final gesture = await tester.startGesture(box.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    await gesture.moveTo(box.centerRight + const Offset(6, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(inkAlpha(tester), 1);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a scroll that takes the press cancels the ripple and the tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: ChromeInk(
                kind: ChromeInkKind.ripple,
                color: _color,
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    expect(inkAlpha(tester), 1);

    // A drag along the list, still over the target, wins the press for the
    // scroll.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, -8));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 160));
    expect(inkAlpha(tester), isNull);
    await gesture.up();
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('a highlight drops when the finger leaves the target, comes '
      'back with it, and taps on a lift over it', (tester) async {
    await tester.pumpWidget(target(ChromeInkKind.highlight));
    final box = tester.getRect(find.byType(ChromeInk));
    final gesture = await tester.startGesture(box.center);
    await tester.pump();
    expect(inkAlpha(tester), 1);

    // Within 70 of the box it stays.
    await gesture.moveTo(box.centerRight + const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(inkAlpha(tester), 1);

    await gesture.moveTo(box.centerRight + const Offset(80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(inkAlpha(tester), closeTo(0.5, 0.05));

    await gesture.moveTo(box.center);
    await tester.pump();
    expect(inkAlpha(tester), 1);

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a highlight lifted away from the target does not tap', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkKind.highlight));
    final box = tester.getRect(find.byType(ChromeInk));
    final gesture = await tester.startGesture(box.center);
    await tester.pump();
    await gesture.moveTo(box.centerRight + const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 310));
    expect(inkAlpha(tester), isNull);
    expect(taps, 0);
  });

  testWidgets('without a tap it draws nothing and takes no tap', (
    tester,
  ) async {
    await tester.pumpWidget(target(ChromeInkKind.highlight, enabled: false));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChromeInk)),
    );
    await tester.pump();
    expect(inkAlpha(tester), isNull);
    await gesture.up();
    expect(taps, 0);
  });
}
