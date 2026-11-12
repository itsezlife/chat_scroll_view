import 'package:bulletins/bulletins.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'android_harness.dart';

void main() {
  late AndroidHarness h;

  tearDown(() => h.dispose());

  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  group('enter', () {
    testWidgets('the card starts its own height and both insets below its '
        'place, behind the obstruction edge', (tester) async {
      h = AndroidHarness(obstruction: const EdgeInsets.only(bottom: 100));
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      final surface = tester.getRect(find.byType(BulletinHost));
      final freeBottom = surface.bottom - 100;
      expect(
        tester.getRect(find.byType(BulletinCard)).top,
        closeTo(freeBottom + 8, 0.01),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(BulletinCard)).bottom, freeBottom - 8);
    });
  });

  group('press', () {
    testWidgets('a bulletin without a tap callback does not scale', (
      tester,
    ) async {
      h = AndroidHarness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BulletinCard)),
      );
      await tester.pump();
      expect(scaleOf(tester), 1);
      // The press still holds the timer.
      expect(handle.isPaused, isTrue);
      await gesture.up();
    });

    testWidgets('a tappable bulletin shrinks to 0.98 while pressed', (
      tester,
    ) async {
      h = AndroidHarness();
      await tester.pumpWidget(h.app());
      h.controller.show(Bulletin(message: 'Copied', onTap: () {}));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BulletinCard)),
      );
      await tester.pump();
      expect(scaleOf(tester), 0.98);
      await gesture.up();
      await tester.pump();
      expect(scaleOf(tester), 1);
    });
  });

  group('swipe', () {
    testWidgets('a short fast fling throws it away', (tester) async {
      h = AndroidHarness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(BulletinCard), const Offset(60, 0), 3000);
      await tester.pump();
      expect(handle.exit, BulletinExit.swiped);
      await tester.pump(const Duration(milliseconds: 16));
      final moving = tester.getRect(find.byType(BulletinCard)).left;
      expect(
        moving,
        greaterThan(tester.getRect(find.byType(BulletinHost)).left + 16 + 60),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copied'), findsNothing);
    });

    testWidgets('a drag during the enter does not move the card', (
      tester,
    ) async {
      h = AndroidHarness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(handle.isEntered, isFalse);
      final card = tester.getRect(find.byType(BulletinCard));
      await tester.dragFrom(
        card.topCenter + const Offset(0, 4),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();
      expect(handle.isClosed, isFalse);
      expect(
        tester.getRect(find.byType(BulletinCard)).left,
        tester.getRect(find.byType(BulletinHost)).left + 16,
      );
    });

    testWidgets('on a wide surface the card fades as it is dragged', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      h = AndroidHarness(surface: const Size(1000, 800));
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final rest = tester.getRect(find.byType(BulletinCard)).center.dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BulletinCard)),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(BulletinCard),
          matching: find.byType(Opacity),
        ),
      );
      final width = tester.getSize(find.byType(BulletinCard)).width;
      final dx = tester.getRect(find.byType(BulletinCard)).center.dx - rest;
      expect(opacity.opacity, closeTo(1 - dx / width, 0.01));
      expect(opacity.opacity, lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('on a phone the card stays opaque as it is dragged', (
      tester,
    ) async {
      h = AndroidHarness();
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BulletinCard)),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(
        find.ancestor(
          of: find.byType(BulletinCard),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
