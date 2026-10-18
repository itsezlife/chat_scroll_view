/// The two-page card: the main row and the More page turned by one progress.
///
/// **Seam:** `SelectionMenuSwipeBack` under a `SelectionMenuPageController`,
/// read through laid-out sizes, global rects, the paint calls, hit tests and a
/// fake clock.
library;

import 'package:chat_composer/src/menu/selection_menu_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/spoken_labels.dart';

void main() {
  const rootKey = Key('root');
  const foregroundKey = Key('foreground');
  const cubic = Cubic(0.25, 0.1, 0.25, 1);
  const rootSize = Size(100, 50);
  const foregroundSize = Size(200, 150);

  late SelectionMenuPageController controller;
  var rootTaps = 0;
  var foregroundTaps = 0;

  setUp(() {
    controller = SelectionMenuPageController();
    rootTaps = 0;
    foregroundTaps = 0;
  });
  tearDown(() => controller.dispose());

  Future<void> pumpHost(
    WidgetTester tester, {
    double initialProgress = 0,
    Duration duration = const Duration(milliseconds: 300),
    Color dim = const Color(0x40000000),
    double maxWidth = 400,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SelectionMenuSwipeBack(
            controller: controller,
            initialProgress: initialProgress,
            pageColor: const Color(0xFFFFFFFF),
            dim: dim,
            duration: duration,
            curve: cubic,
            borderRadius: 12,
            root: SizedBox.fromSize(
              size: rootSize,
              child: TextButton(
                key: rootKey,
                onPressed: () => rootTaps++,
                child: const Text('Root'),
              ),
            ),
            foreground: SizedBox.fromSize(
              size: foregroundSize,
              child: TextButton(
                key: foregroundKey,
                onPressed: () => foregroundTaps++,
                child: const Text('Foreground'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Size hostSize(WidgetTester tester) =>
      tester.getSize(find.byType(SelectionMenuSwipeBack));

  group('turning', () {
    testWidgets('a full open and a full close take 300 ms', (tester) async {
      await pumpHost(tester);

      // A ticker reports done on the first frame past its duration.
      controller.openForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 299));
      expect(controller.progress, lessThan(1));
      await tester.pump(const Duration(milliseconds: 2));
      expect(controller.progress, 1);
      expect(controller.isForegroundOpen, isTrue);

      controller.closeForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 299));
      expect(controller.progress, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 2));
      expect(controller.progress, 0);
      expect(controller.isForegroundOpen, isFalse);
    });

    testWidgets('the turn follows the CSS ease cubic', (tester) async {
      await pumpHost(tester);

      controller.openForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.progress, closeTo(cubic.transform(0.5), 1e-6));
    });

    testWidgets('a turn that starts half way takes half as long', (
      tester,
    ) async {
      await pumpHost(tester);
      controller.scrubTo(0.5);

      controller.openForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 151));

      expect(controller.progress, 1);
    });

    testWidgets('a turn is never shorter than half the full time', (
      tester,
    ) async {
      await pumpHost(tester);
      controller.scrubTo(0.9);

      controller.openForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 149));

      expect(controller.progress, lessThan(1));
    });

    testWidgets('open and close are ignored while a turn is running', (
      tester,
    ) async {
      await pumpHost(tester);

      controller.openForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = controller.progress;
      controller.closeForeground();
      controller.openForeground();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.progress, greaterThan(mid));
      await tester.pumpAndSettle();
      expect(controller.progress, 1);
    });

    testWidgets('a zero duration, as under reduce-motion, turns at once', (
      tester,
    ) async {
      await pumpHost(tester, duration: Duration.zero);

      controller.openForeground();
      await tester.pump();

      expect(controller.progress, 1);
    });

    testWidgets('initialProgress starts on the More page', (tester) async {
      await pumpHost(tester, initialProgress: 1);

      expect(controller.progress, 1);
      expect(hostSize(tester), foregroundSize);
    });
  });

  group('size and paint', () {
    testWidgets('the card is the root, the More page, or a blend of them', (
      tester,
    ) async {
      await pumpHost(tester);
      expect(hostSize(tester), rootSize);

      controller.scrubTo(0.5);
      await tester.pump();
      expect(hostSize(tester).width, closeTo(150, 1e-6));
      expect(hostSize(tester).height, closeTo(100, 1e-6));

      controller.scrubTo(1);
      await tester.pump();
      expect(hostSize(tester), foregroundSize);
    });

    testWidgets('the root slides left by half the card and shrinks to 0.95', (
      tester,
    ) async {
      await pumpHost(tester);
      controller.scrubTo(0.4);
      await tester.pump();

      final host = hostSize(tester);
      final root = tester.getRect(find.byKey(rootKey));
      // Translate by -0.4 * 0.5 * width, then scale by 0.95 + 0.6 * 0.05.
      expect(root.left, closeTo(-0.4 * 0.5 * host.width, 1e-6));
      expect(root.width, closeTo(rootSize.width * 0.98, 1e-6));
      expect(root.top, closeTo(0, 1e-6));
    });

    testWidgets('the More page slides in from the right', (tester) async {
      await pumpHost(tester);
      controller.scrubTo(0.4);
      await tester.pump();

      final host = hostSize(tester);
      final foreground = tester.getRect(find.byKey(foregroundKey));
      expect(foreground.left, closeTo(0.6 * host.width, 1e-6));
    });

    testWidgets('the More page is not mirrored in right-to-left', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SelectionMenuSwipeBack(
                controller: controller,
                initialProgress: 0,
                pageColor: const Color(0xFFFFFFFF),
                dim: const Color(0x40000000),
                duration: const Duration(milliseconds: 300),
                curve: cubic,
                borderRadius: 12,
                root: SizedBox.fromSize(size: rootSize),
                foreground: SizedBox.fromSize(
                  size: foregroundSize,
                  child: const Text('F', key: foregroundKey),
                ),
              ),
            ),
          ),
        ),
      );
      controller.scrubTo(0.4);
      await tester.pump();

      expect(
        tester.getRect(find.byKey(foregroundKey)).left,
        greaterThan(hostSize(tester).width / 2),
      );
    });

    RenderObject renderObject(WidgetTester tester) => tester.renderObject(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_SwipeBackRender',
      ),
    );

    const white = Color(0xFFFFFFFF);

    testWidgets('the dim scales with the progress up to the token\'s alpha', (
      tester,
    ) async {
      await pumpHost(tester, dim: const Color(0x40000000));

      // Closed: the root's page fill and nothing else.
      expect(renderObject(tester), paintsExactlyCountTimes(#drawRect, 1));

      controller.scrubTo(0.5);
      await tester.pump();
      // 0.5 * 0x40 = 32, between the root's page and the More page's.
      expect(
        renderObject(tester),
        paints
          ..rect(color: white)
          ..rect(color: const Color.fromARGB(32, 0, 0, 0))
          ..rect(color: white),
      );

      controller.scrubTo(1);
      await tester.pump();
      expect(
        renderObject(tester),
        paints
          ..rect(color: const Color.fromARGB(0x40, 0, 0, 0))
          ..rect(color: white),
      );
    });

    testWidgets('a light dim is the softer 0x18', (tester) async {
      await pumpHost(tester, dim: const Color(0x18000000));
      controller.scrubTo(1);
      await tester.pump();

      expect(
        renderObject(tester),
        paints..rect(color: const Color.fromARGB(0x18, 0, 0, 0)),
      );
    });

    testWidgets('the root is not painted once the More page covers it', (
      tester,
    ) async {
      await pumpHost(tester, initialProgress: 1);

      expect(tester.takeException(), isNull);
      expect(find.text('Root').hitTestable(), findsNothing);
    });

    testWidgets('does not overflow under a tight width', (tester) async {
      await pumpHost(tester, maxWidth: 160);

      controller.openForeground();
      await tester.pumpAndSettle();
      controller.closeForeground();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('who answers', () {
    testWidgets('the root answers a tap while the row shows', (tester) async {
      await pumpHost(tester);

      await tester.tap(find.byKey(rootKey));

      expect(rootTaps, 1);
      expect(foregroundTaps, 0);
    });

    testWidgets('the More page answers once past half way, the root before', (
      tester,
    ) async {
      await pumpHost(tester);

      // Past half way the card is 160 by 110 and the More page starts at
      // x = 64; the root has slid off to the left.
      controller.scrubTo(0.6);
      await tester.pump();
      await tester.tapAt(const Offset(100, 30));
      expect(foregroundTaps, 1);
      expect(rootTaps, 0);

      // Before half way the root answers where it is.
      controller.scrubTo(0.4);
      await tester.pump();
      await tester.tapAt(const Offset(30, 20));
      expect(rootTaps, 1);
      expect(foregroundTaps, 1);
    });

    testWidgets('semantics follow the page that shows', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(tester);

      expect(spokenLabels(tester), contains('Root'));
      expect(spokenLabels(tester), isNot(contains('Foreground')));

      controller.openForeground();
      await tester.pumpAndSettle();

      expect(spokenLabels(tester), isNot(contains('Root')));
      expect(spokenLabels(tester), contains('Foreground'));
      handle.dispose();
    });

    testWidgets('focus follows the page that shows', (tester) async {
      await pumpHost(tester);
      bool focusable(String label) =>
          Focus.of(tester.element(find.text(label))).canRequestFocus;

      expect(focusable('Root'), isTrue);
      expect(focusable('Foreground'), isFalse);

      controller.openForeground();
      await tester.pumpAndSettle();

      expect(focusable('Root'), isFalse);
      expect(focusable('Foreground'), isTrue);
    });
  });

  group('swipe', () {
    // A touch drag begins where the finger crosses the slop, so the first move
    // only starts it; the rest is what scrubs.
    Future<void> dragRight(WidgetTester tester, double total) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(foregroundKey)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(Offset(total - 30, 0));
      await tester.pump();
      await gesture.up();
    }

    testWidgets('a drag to the right scrubs the page back with the finger', (
      tester,
    ) async {
      await pumpHost(tester, initialProgress: 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(foregroundKey)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();

      // 50 of the page's 200 dp: a quarter of the way back.
      expect(controller.progress, closeTo(0.75, 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a slow drag past half way closes the page', (tester) async {
      await pumpHost(tester, initialProgress: 1);

      await dragRight(tester, 150);
      await tester.pumpAndSettle();

      expect(controller.progress, 0);
    });

    testWidgets('a slow drag short of half way springs back open', (
      tester,
    ) async {
      await pumpHost(tester, initialProgress: 1);

      await dragRight(tester, 40);
      await tester.pumpAndSettle();

      expect(controller.progress, 1);
    });

    testWidgets('a fling of 600 dp/s or more closes it from a short drag', (
      tester,
    ) async {
      await pumpHost(tester, initialProgress: 1);

      await tester.flingFrom(
        tester.getCenter(find.byKey(foregroundKey)),
        const Offset(60, 0),
        700,
      );
      await tester.pumpAndSettle();

      expect(controller.progress, 0);
    });

    testWidgets('a fling under 600 dp/s does not', (tester) async {
      await pumpHost(tester, initialProgress: 1);

      await tester.flingFrom(
        tester.getCenter(find.byKey(foregroundKey)),
        const Offset(60, 0),
        400,
      );
      await tester.pumpAndSettle();

      expect(controller.progress, 1);
    });

    testWidgets('a drag to the left does not turn the page', (tester) async {
      await pumpHost(tester, initialProgress: 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(foregroundKey)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-80, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.progress, 1);
    });

    testWidgets('a drag does not start while the page is turning', (
      tester,
    ) async {
      await pumpHost(tester);
      controller.openForeground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = controller.progress;

      final gesture = await tester.startGesture(const Offset(50, 25));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(80, 0));
      await gesture.up();

      expect(controller.progress, greaterThanOrEqualTo(mid));
      await tester.pumpAndSettle();
    });

    testWidgets('a fling closes in less than a full turn', (tester) async {
      await pumpHost(tester, initialProgress: 1);
      controller.scrubTo(0.9);

      controller.snapFromFling(velocityX: 2000, width: 200);
      await tester.pump();
      // 0.9 away, less 0.2 for the fling: 0.7 of 300 ms.
      await tester.pump(const Duration(milliseconds: 209));
      expect(controller.progress, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 2));
      expect(controller.progress, 0);
    });
  });
}
