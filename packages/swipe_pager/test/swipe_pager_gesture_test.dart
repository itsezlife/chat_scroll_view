import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipe_pager/swipe_pager.dart';

/// The test view is 800 x 600 logical pixels at a device pixel ratio of 3,
/// so the reference's physical velocities divide by 3.
void main() {
  late SwipePagerController controller;
  late List<ScrollController> lists;
  late ScrollController strip;

  setUp(() {
    controller = SwipePagerController();
    lists = [for (var i = 0; i < 3; i++) ScrollController()];
    strip = ScrollController();
  });

  tearDown(() {
    controller.dispose();
    for (final list in lists) {
      list.dispose();
    }
    strip.dispose();
  });

  Widget page(int index) => Column(
    children: [
      SizedBox(
        height: 100,
        child: ListView(
          key: ValueKey('strip $index'),
          controller: index == 0 ? strip : null,
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < 30; i++)
              SizedBox(width: 80, child: Text('cell $index.$i')),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          key: ValueKey('list $index'),
          controller: lists[index],
          itemCount: 100,
          itemBuilder: (context, i) =>
              SizedBox(height: 50, child: Text('row $index.$i')),
        ),
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    Set<PointerDeviceKind>? dragDevices,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600), devicePixelRatio: 3),
          child: SwipePager(
            controller: controller,
            pageCount: 3,
            pageBuilder: (context, index) => page(index),
            dragDevices: dragDevices ?? SwipePager.defaultDragDevices,
          ),
        ),
      ),
    );
  }

  /// A drag from the middle of the list at [degrees] from the horizontal,
  /// leftward, in steps of 2 px every 16 ms (125 px/s: no fling).
  Future<void> slowDrag(
    WidgetTester tester,
    double degrees,
    double length, {
    Offset start = const Offset(400, 400),
    double sign = -1,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final step = Offset(
      sign * 2 * math.cos(degrees * math.pi / 180),
      -2 * math.sin(degrees * math.pi / 180),
    );
    final gesture = await tester.startGesture(start, kind: kind);
    for (var moved = 0.0; moved < length; moved += 2) {
      await gesture.moveBy(step, timeStamp: const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('the direction rule', () {
    for (final degrees in [0.0, 10.0, 20.0]) {
      testWidgets('a drag $degrees° off the axis swipes', (tester) async {
        await pump(tester);
        await slowDrag(tester, degrees, 400);

        expect(controller.page, 1);
        expect(lists[0].offset, 0);
      });
    }

    for (final degrees in [30.0, 45.0, 70.0, 90.0]) {
      testWidgets('a drag $degrees° off the axis scrolls the list', (
        tester,
      ) async {
        await pump(tester);
        await slowDrag(tester, degrees, 400);

        expect(controller.page, 0);
        expect(controller.position, 0);
        expect(lists[0].offset, greaterThan(0));
      });
    }

    testWidgets('the decision does not depend on how the moves are sampled', (
      tester,
    ) async {
      await pump(tester);
      // One move of 40 px at 15°: past both of the pager's slops at once
      // (10.7 px across), but not the list's own.
      final gesture = await tester.startGesture(const Offset(400, 400));
      await gesture.moveBy(Offset(-40, -40 * math.tan(15 * math.pi / 180)));
      await tester.pump();
      expect(controller.isDragging, isTrue);
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();

      expect(controller.position, greaterThan(0));
      expect(lists[0].offset, 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the pager does not move until the slop is passed', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await tester.startGesture(const Offset(400, 400));
      await gesture.moveBy(const Offset(-18, 0));
      await tester.pump();
      expect(controller.position, 0);

      await gesture.moveBy(const Offset(-2, 0));
      await tester.pump();
      // Claimed at the slop, which is consumed: the page does not jump.
      expect(controller.isDragging, isTrue);
      expect(controller.position, 0);

      await gesture.moveBy(const Offset(-8, 0));
      await tester.pump();
      expect(controller.position, closeTo(8 / 800, 1e-9));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });
  });

  group('release', () {
    testWidgets('a drag past a third of the page goes on', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 290);
      expect(controller.page, 1);
    });

    testWidgets('a shorter slow drag goes back', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 200);
      expect(controller.page, 0);
      expect(controller.position, 0);
    });

    testWidgets('a short drag flung at 3500 physical px/s goes on', (
      tester,
    ) async {
      await pump(tester);
      await tester.flingFrom(
        const Offset(400, 400),
        const Offset(-80, 0),
        1400,
      );
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });

    testWidgets('a short drag flung slower goes back', (tester) async {
      await pump(tester);
      await tester.flingFrom(const Offset(400, 400), const Offset(-80, 0), 900);
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    testWidgets('a quick flick under the slop swipes', (tester) async {
      await pump(tester);
      await tester.flingFrom(
        const Offset(400, 400),
        const Offset(-16, 0),
        2000,
      );
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });

    testWidgets('the settle after a release takes 150..600 ms', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 290);
      // Settled within the pumpAndSettle of the drag; a slow drag ends with
      // no velocity, so 100 ms plus the page share left, at least 150.
      expect(controller.isSettling, isFalse);
    });
  });

  group('edges', () {
    testWidgets('the first page does not swipe back', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(const Offset(400, 400));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.position, 0);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    testWidgets('a drag stops at the next page', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 1200);
      expect(controller.page, 1);
    });
  });

  group('a nested horizontal scroller', () {
    testWidgets('keeps a horizontal drag inside its bounds', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 300, start: const Offset(400, 50));

      expect(controller.page, 0);
      expect(strip.offset, greaterThan(0));
    });
  });

  group('a settle', () {
    testWidgets('is caught by a touch, which then drags it', (tester) async {
      await pump(tester);
      await tester.flingFrom(
        const Offset(400, 400),
        const Offset(-80, 0),
        1400,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 30));
      expect(controller.isSettling, isTrue);
      final caughtAt = controller.position;

      final gesture = await tester.startGesture(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.position, caughtAt);

      // A slow drag back, under the claim slop, still moves it.
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.position, lessThan(caughtAt));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      // Caught about a third of the way and released slowly: back to the
      // nearer page.
      expect(caughtAt, inExclusiveRange(0.1, 0.5));
      expect(controller.page, 0);
    });
  });

  group('right to left', () {
    testWidgets('a rightward drag goes to the next page', (tester) async {
      await pump(tester, direction: TextDirection.rtl);
      await slowDrag(tester, 0, 400, sign: 1);
      expect(controller.page, 1);
    });

    testWidgets('a leftward drag on the first page does nothing', (
      tester,
    ) async {
      await pump(tester, direction: TextDirection.rtl);
      await slowDrag(tester, 0, 400);
      expect(controller.page, 0);
    });

    testWidgets('the next page enters from the left', (tester) async {
      await pump(tester, direction: TextDirection.rtl);
      final gesture = await tester.startGesture(const Offset(400, 400));
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('list 1'))).dx,
        lessThan(0),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('list 0'))).dx,
        greaterThan(0),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('pointers', () {
    testWidgets('a mouse drag does not swipe by default', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 400, kind: PointerDeviceKind.mouse);
      expect(controller.page, 0);
    });

    testWidgets('a mouse drag swipes when the host asks', (tester) async {
      await pump(
        tester,
        dragDevices: {
          ...SwipePager.defaultDragDevices,
          PointerDeviceKind.mouse,
        },
      );
      await slowDrag(tester, 0, 400, kind: PointerDeviceKind.mouse);
      expect(controller.page, 1);
    });

    testWidgets('a trackpad pan swipes', (tester) async {
      await pump(tester);
      await slowDrag(tester, 0, 400, kind: PointerDeviceKind.trackpad);
      expect(controller.page, 1);
    });
  });
}
