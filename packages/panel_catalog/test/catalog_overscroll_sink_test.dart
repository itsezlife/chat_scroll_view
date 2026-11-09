/// The part of a drag the catalogue cannot scroll past its top edge, handed
/// to the host's receiver.
///
/// **Seam:** [PanelCatalogViewport] with an `overscrollSink` from a
/// [FakeCatalogOverscrollSink], driven by pointer gestures; observed through
/// what the receiver was offered and released, the controller's `offset`
/// and its scroll events. The contract every receiver meets runs against
/// the fake here.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

CatalogSection _section(int count) => CatalogSection(
  id: 's',
  title: 's',
  leaves: [
    for (var i = 0; i < count; i++)
      CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
  ],
);

// A 320 x 480 viewport at the centre of the 800 x 600 test screen: four
// columns of 40 px cells under a 24 px header.
const _centre = Offset(400, 300);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<PanelCatalogScrollEvent> events;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    events = [];
    final subscription = controller.events.listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      controller.dispose();
      snapshots.dispose();
    });
  });

  // [count] leaves: 200 are 50 rows, far taller than the viewport; 4 fit.
  Future<FakeCatalogOverscrollSink> pump(
    WidgetTester tester, {
    int count = 200,
    FakeCatalogOverscrollSink? receiver,
  }) async {
    final sink = receiver ?? FakeCatalogOverscrollSink();
    snapshots.replaceSections([_section(count)]);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: PanelCatalogThemeData.light,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: textGlyphScope(),
                controller: controller,
                spanCount: 4,
                cellExtent: 40,
                headerExtent: 24,
                overscrollSink: sink.sink,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return sink;
  }

  // A finger that crosses the slop, then moves [steps] of [step], [gap]
  // apart in event time; returns it still down.
  Future<TestGesture> drag(
    WidgetTester tester, {
    required double step,
    required int steps,
    Duration gap = const Duration(milliseconds: 16),
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    var time = Duration.zero;
    final finger = await tester.startGesture(_centre, kind: kind);
    time += gap;
    await finger.moveBy(Offset(0, step.sign * 20), timeStamp: time);
    for (var i = 0; i < steps; i++) {
      time += gap;
      await finger.moveBy(Offset(0, step), timeStamp: time);
    }
    await tester.pump();
    return finger;
  }

  group('at the top', () {
    testWidgets('a pull goes to the receiver and the content stays', (
      tester,
    ) async {
      final receiver = await pump(tester);

      final finger = await drag(tester, step: 10, steps: 6);

      // 20 past the slop, then 60.
      expect(receiver.held, 80);
      expect(controller.offset, 0);
      await finger.up();
    });

    testWidgets('a push is offered first, and scrolls the content once the '
        'receiver declines it', (tester) async {
      final receiver = await pump(tester);

      final finger = await drag(tester, step: -10, steps: 6);

      expect(receiver.offers.first, lessThan(0));
      expect(receiver.held, 0);
      expect(controller.offset, 80);
      await finger.up();
    });

    testWidgets('a push gives back what the receiver holds before the '
        'content scrolls', (tester) async {
      final receiver = await pump(tester);
      final finger = await drag(tester, step: 10, steps: 4);
      expect(receiver.held, 60);

      for (var i = 0; i < 8; i++) {
        await finger.moveBy(const Offset(0, -10));
      }
      await tester.pump();

      expect(receiver.held, 0);
      expect(controller.offset, 20);
      await finger.up();
    });

    testWidgets('content that fits hands over every pull', (tester) async {
      final receiver = await pump(tester, count: 4);

      final finger = await drag(tester, step: 10, steps: 6);

      expect(receiver.held, 80);
      await finger.up();
    });
  });

  group('away from the top', () {
    testWidgets('a pull scrolls the content back first and offers only the '
        'rest', (tester) async {
      final receiver = await pump(tester);
      controller.jumpTo(30);
      await tester.pump();

      final finger = await drag(tester, step: 10, steps: 6);

      // 20 past the slop, then 60: 30 scroll the content, 50 go past the top.
      expect(controller.offset, 0);
      expect(receiver.offeredTotal, 50);
      expect(receiver.held, 50);
      await finger.up();
    });

    testWidgets('a push is never offered', (tester) async {
      final receiver = await pump(tester);
      controller.jumpTo(30);
      await tester.pump();

      final finger = await drag(tester, step: -10, steps: 6);

      expect(receiver.offers, isEmpty);
      await finger.up();
    });
  });

  group('release', () {
    testWidgets('a receiver that takes it stops the content fling', (
      tester,
    ) async {
      final receiver = await pump(tester);

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, 120),
        2000,
      );
      await tester.pump();

      expect(receiver.releases.single, greaterThan(0));
      expect(events.whereType<PanelCatalogFlingStart>(), isEmpty);
    });

    testWidgets('one that gave everything back lets the content fling', (
      tester,
    ) async {
      final receiver = await pump(tester);
      final finger = await drag(tester, step: 10, steps: 2);

      var time = const Duration(milliseconds: 48);
      for (var i = 0; i < 12; i++) {
        time += const Duration(milliseconds: 8);
        await finger.moveBy(const Offset(0, -30), timeStamp: time);
      }
      await finger.up(timeStamp: time + const Duration(milliseconds: 8));
      await tester.pump();

      expect(receiver.releases.single, lessThan(0));
      expect(events.whereType<PanelCatalogFlingStart>(), hasLength(1));
      await tester.pumpAndSettle();
    });

    testWidgets('a drag it took no part in is not reported to it', (
      tester,
    ) async {
      final receiver = await pump(tester);

      final finger = await drag(tester, step: -10, steps: 6);
      await finger.up();
      await tester.pumpAndSettle();

      expect(receiver.releases, isEmpty);
    });

    testWidgets('a cancelled drag releases it once', (tester) async {
      final receiver = await pump(tester);
      final finger = await drag(tester, step: 10, steps: 3);

      await finger.cancel();
      await tester.pump();

      expect(receiver.releases, hasLength(1));
    });
  });

  group('a scroll that reaches the top', () {
    testWidgets('hands its overflow over on the same tick', (tester) async {
      final receiver = await pump(tester);
      controller.jumpTo(30);
      await tester.pump();
      // 20 past the slop scroll the content to 10.
      final finger = await drag(tester, step: 10, steps: 0);
      expect(controller.offset, 10);
      expect(receiver.offers, isEmpty);

      await finger.moveBy(
        const Offset(0, 30),
        timeStamp: const Duration(milliseconds: 32),
      );

      expect(controller.offset, 0);
      expect(receiver.offers, [20]);
      expect(receiver.held, 20);
      await finger.up();
    });

    testWidgets('reports the velocity of the pull it handed over, not of '
        'the whole drag', (tester) async {
      final receiver = await pump(tester);
      controller.jumpTo(340);
      await tester.pump();

      // 120 px every 8 ms (15000 px/s) scroll the content to its top and 20
      // past it; then the finger slows to 2 px every 16 ms and lifts.
      var time = Duration.zero;
      final finger = await tester.startGesture(_centre);
      for (var i = 0; i < 3; i++) {
        time += const Duration(milliseconds: 8);
        await finger.moveBy(const Offset(0, 120), timeStamp: time);
      }
      for (var i = 0; i < 2; i++) {
        time += const Duration(milliseconds: 16);
        await finger.moveBy(const Offset(0, 2), timeStamp: time);
      }
      await finger.up(timeStamp: time);
      await tester.pump();

      final drag = events.whereType<PanelCatalogUserDragEnd>().single;
      expect(drag.velocity.abs(), greaterThan(3500));
      expect(receiver.releases.single, inInclusiveRange(0, 500));
    });
  });

  group('never offered', () {
    testWidgets('the mouse wheel at the top', (tester) async {
      final receiver = await pump(tester);

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: _centre,
          scrollDelta: Offset(0, -100),
        ),
      );
      await tester.pump();

      expect(receiver.offers, isEmpty);
    });

    testWidgets('a mouse press-and-move', (tester) async {
      final receiver = await pump(tester);

      final mouse = await drag(
        tester,
        step: 10,
        steps: 6,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();

      expect(receiver.offers, isEmpty);
    });

    testWidgets('a programmatic scroll to the top', (tester) async {
      final receiver = await pump(tester);
      controller.jumpTo(200);
      await tester.pump();

      controller.scrollBy(-400);
      await tester.pump();

      expect(receiver.offers, isEmpty);
    });
  });

  group('FakeCatalogOverscrollSink', () {
    CatalogOverscrollSinkContract.run(
      (tester) async => CatalogOverscrollSinkHarness(
        sink: FakeCatalogOverscrollSink().sink,
        settle: () async {},
      ),
    );
  });
}
