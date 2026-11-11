/// The catalogue scrolls with the chat's scroll physics: the same fling and
/// edge effect, the platform's preset by default, and the overscroll sink
/// still served first at the top.
///
/// **Seam:** [PanelCatalogViewport] with `physics`, driven by pointer
/// gestures; observed through the controller's offset, the render object's
/// fling flag and the edge effect's paint transform.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:viewport_scroll/engine.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

import 'support/asset_scopes.dart';

CatalogSection _section(int count) => CatalogSection(
  id: 's',
  title: 's',
  leaves: [
    for (var i = 0; i < count; i++)
      CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
  ],
);

// A 320 x 480 viewport at the centre of the 800 x 600 test screen.
const _centre = Offset(400, 300);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<CatalogLeafHit> taps;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    taps = [];
    addTearDown(() {
      controller.dispose();
      snapshots.dispose();
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    ViewportScrollPhysics? physics,
    int count = 200,
    CatalogOverscrollSink? sink,
  }) async {
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
                physics: physics,
                overscrollSink: sink,
                onLeafTap: taps.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  RenderPanelCatalog render(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  // A finger that crosses the slop, then moves [steps] of [step]; still down.
  Future<TestGesture> drag(
    WidgetTester tester, {
    required double step,
    required int steps,
  }) async {
    var time = Duration.zero;
    final finger = await tester.startGesture(_centre);
    time += const Duration(milliseconds: 16);
    await finger.moveBy(Offset(0, step.sign * 20), timeStamp: time);
    for (var i = 0; i < steps; i++) {
      time += const Duration(milliseconds: 16);
      await finger.moveBy(Offset(0, step), timeStamp: time);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return finger;
  }

  group('the preset', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    ]) {
      testWidgets("is the platform's when none is given ($platform)", (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        await pump(tester);
        expect(
          render(tester).physics,
          ViewportScrollPhysics.forPlatform(platform: platform),
        );
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('a new one stops the fling in flight', (tester) async {
      await pump(tester, physics: const ViewportScrollPhysics.stretch());
      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -200),
        2000,
      );
      await tester.pump();
      expect(render(tester).isFlinging, isTrue);

      await pump(tester, physics: const ViewportScrollPhysics.rubberBand());

      expect(render(tester).physics, const ViewportScrollPhysics.rubberBand());
      expect(render(tester).isFlinging, isFalse);
    });
  });

  group('the fling', () {
    for (final physics in const [
      ViewportScrollPhysics.stretch(),
      ViewportScrollPhysics.rubberBand(),
    ]) {
      testWidgets('travels as ${physics.fling} does', (tester) async {
        await pump(tester, physics: physics, count: 4000);
        await tester.fling(
          find.byType(PanelCatalogViewport),
          const Offset(0, -100),
          1500,
        );
        final released = controller.offset;
        await tester.pumpAndSettle();
        final travel = controller.offset - released;

        // The curve's own travel from the release speed the drag measured.
        final runner = ViewportFlingMotion(physics.fling)..startFling(1500);
        var expected = 0.0;
        for (var t = 0; runner.isFlinging && t < 20000; t += 16) {
          expected += runner.tickFling(Duration(milliseconds: t));
        }
        expect(travel, closeTo(expected, expected * 0.1));
      });
    }
  });

  group('the edge effect', () {
    testWidgets('stretch: a pull at the top scales the content and springs '
        'back on release', (tester) async {
      await pump(tester, physics: const ViewportScrollPhysics.stretch());

      final finger = await drag(tester, step: 10, steps: 8);
      expect(controller.offset, 0);
      final pulled = render(tester).edgeTransform;
      expect(pulled, isNotNull);
      expect(pulled!.getMaxScaleOnAxis(), greaterThan(1));

      await finger.up();
      await tester.pumpAndSettle();
      expect(render(tester).edgeTransform, isNull);
    });

    testWidgets('rubber band: a push at the bottom moves the content up and '
        'springs back on release', (tester) async {
      await pump(tester, physics: const ViewportScrollPhysics.rubberBand());
      controller.jumpTo(render(tester).maxOffset);
      await tester.pump();

      final finger = await drag(tester, step: -10, steps: 8);
      final pushed = render(tester).edgeTransform;
      expect(pushed, isNotNull);
      expect(pushed!.getTranslation().y, lessThan(0));

      await finger.up();
      await tester.pumpAndSettle();
      expect(render(tester).edgeTransform, isNull);
      expect(controller.offset, render(tester).maxOffset);
    });

    testWidgets('clamped: a pull at the top shows nothing', (tester) async {
      await pump(tester, physics: const ViewportScrollPhysics.clamped());

      final finger = await drag(tester, step: 10, steps: 8);
      expect(render(tester).edgeTransform, isNull);
      await finger.up();
    });

    testWidgets('a fling into the bottom bounces with a rubber band', (
      tester,
    ) async {
      await pump(tester, physics: const ViewportScrollPhysics.rubberBand());
      controller.jumpTo(render(tester).maxOffset - 200);
      await tester.pump();

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -100),
        3000,
      );
      var bounced = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        bounced |= render(tester).edgeTransform != null;
      }
      expect(bounced, isTrue);
      await tester.pumpAndSettle();
      expect(render(tester).edgeTransform, isNull);
      expect(controller.offset, render(tester).maxOffset);
    });

    testWidgets('a press while it springs back catches it and taps nothing', (
      tester,
    ) async {
      await pump(tester, physics: const ViewportScrollPhysics.rubberBand());
      final finger = await drag(tester, step: 10, steps: 8);
      await finger.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(render(tester).edgeTransform, isNotNull);

      await tester.tapAt(_centre);
      await tester.pumpAndSettle();

      expect(taps, isEmpty);
      expect(render(tester).edgeTransform, isNull);
    });

    testWidgets('the overscroll sink is served first at the top', (
      tester,
    ) async {
      final receiver = FakeCatalogOverscrollSink();
      await pump(
        tester,
        physics: const ViewportScrollPhysics.stretch(),
        sink: receiver.sink,
      );

      final finger = await drag(tester, step: 10, steps: 6);
      expect(receiver.held, greaterThan(0));
      expect(controller.offset, 0);
      expect(render(tester).edgeTransform, isNull);
      await finger.up();
      await tester.pumpAndSettle();
    });
  });
}
