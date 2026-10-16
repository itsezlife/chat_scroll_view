/// The pointer seams a host builds a desktop interaction on: the secondary
/// button of a mouse, a long-press delay chosen per pointer kind and cell,
/// and a pinned cell that holds the hover wash and the wheel while a
/// transient surface is open over it.
///
/// **Seam:** [PanelCatalogViewport] driven by [TestGesture]s of one pointer
/// kind and button at a time, observed through the callbacks the host passes,
/// the render object's press state and a recording canvas.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';
import 'support/recording_canvas.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480 viewport.
const _hover = Color(0x14000000);

String _glyph(int i) => String.fromCharCode(0x1F600 + i % 80);

CatalogSection _section(String id, int count) => CatalogSection(
  id: id,
  title: 'Title $id',
  leaves: [for (var i = 0; i < count; i++) CatalogLeaf.unicode(_glyph(i))],
);

// Row 0, columns 0 and 1, under the header.
const _first = Offset(40, 44);
const _second = Offset(120, 44);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource(sections: [_section('a', 120)]);
    controller = PanelCatalogController();
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    ValueChanged<CatalogLeafHit>? onLeafTap,
    void Function(CatalogLeafHit hit, Offset globalPosition)? onSecondaryTap,
    void Function(CatalogLeafHit hit, LongPressStartDetails details)?
    onLongPressStart,
    void Function(CatalogLeafHit hit, LongPressEndDetails details)?
    onLongPressEnd,
    Duration? Function(CatalogLeafHit hit, PointerDeviceKind kind)? delay,
    CatalogLeafHit? pinnedLeaf,
    PanelCatalogThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data:
            theme ??
            PanelCatalogThemeData.light.copyWith(
              leafHoverHighlightColor: _hover,
            ),
        child: Align(
          alignment: Alignment.topLeft,
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
              onLeafTap: onLeafTap,
              onLeafSecondaryTap: onSecondaryTap,
              onLeafLongPressStart: onLongPressStart,
              onLeafLongPressEnd: onLongPressEnd,
              leafLongPressDelay: delay,
              pinnedLeaf: pinnedLeaf,
            ),
          ),
        ),
      ),
    ),
  );

  RenderPanelCatalog render(WidgetTester tester) => tester
      .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport));

  Future<TestGesture> mouse(
    WidgetTester tester, {
    int buttons = kPrimaryMouseButton,
  }) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await gesture.addPointer(location: const Offset(700, 500));
    addTearDown(gesture.removePointer);
    return gesture;
  }

  group('secondary tap', () {
    testWidgets('a mouse right click reports the cell and where it was', (
      tester,
    ) async {
      final seen = <(CatalogLeafHit, Offset)>[];
      await pumpViewport(
        tester,
        onSecondaryTap: (hit, position) => seen.add((hit, position)),
      );
      final gesture = await mouse(tester, buttons: kSecondaryMouseButton);

      await gesture.down(_second);
      await gesture.up();
      await tester.pump();

      expect(seen, hasLength(1));
      expect(seen.single.$1.sectionId, 'a');
      expect(seen.single.$1.index, 1);
      expect(seen.single.$2, _second);
    });

    testWidgets('a right click does not tap, press or long-press the cell', (
      tester,
    ) async {
      var taps = 0;
      var longPresses = 0;
      await pumpViewport(
        tester,
        onLeafTap: (_) => taps++,
        onSecondaryTap: (_, _) {},
        onLongPressStart: (_, _) => longPresses++,
        onLongPressEnd: (_, _) {},
      );
      final gesture = await mouse(tester, buttons: kSecondaryMouseButton);

      await gesture.down(_first);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      expect(
        render(tester).pressedSlotKey,
        isNull,
        reason: 'a right click does not start the press animation',
      );
      await gesture.up();
      await tester.pump();

      expect(taps, 0);
      expect(longPresses, 0);
    });

    testWidgets('a left click is a tap and never a secondary tap', (
      tester,
    ) async {
      var taps = 0;
      var secondary = 0;
      await pumpViewport(
        tester,
        onLeafTap: (_) => taps++,
        onSecondaryTap: (_, _) => secondary++,
      );
      final gesture = await mouse(tester);

      await gesture.down(_first);
      expect(render(tester).pressedSlotKey, isNotNull);
      await gesture.up();
      await tester.pump();

      expect(taps, 1);
      expect(secondary, 0);
    });

    testWidgets('a right click on a header or in the padding is silent', (
      tester,
    ) async {
      var secondary = 0;
      await pumpViewport(tester, onSecondaryTap: (_, _) => secondary++);
      final gesture = await mouse(tester, buttons: kSecondaryMouseButton);

      await gesture.down(const Offset(40, 10));
      await gesture.up();
      await tester.pump();

      expect(secondary, 0);
    });

    testWidgets('only a mouse: a stylus barrel button is not a right click', (
      tester,
    ) async {
      var secondary = 0;
      await pumpViewport(tester, onSecondaryTap: (_, _) => secondary++);
      final stylus = await tester.createGesture(
        kind: PointerDeviceKind.stylus,
        buttons: kSecondaryStylusButton,
      );

      await stylus.down(_first);
      await stylus.up();
      await tester.pump();

      expect(secondary, 0);
    });

    testWidgets('without the callback a right click does nothing at all', (
      tester,
    ) async {
      var taps = 0;
      await pumpViewport(tester, onLeafTap: (_) => taps++);
      final gesture = await mouse(tester, buttons: kSecondaryMouseButton);

      await gesture.down(_first);
      await gesture.up();
      await tester.pump();

      expect(taps, 0);
      expect(render(tester).pressedSlotKey, isNull);
    });
  });

  group('long-press delay', () {
    testWidgets('a zero delay for a mouse starts the long press on press', (
      tester,
    ) async {
      final started = <CatalogLeafHit>[];
      await pumpViewport(
        tester,
        onLeafTap: (_) {},
        onLongPressStart: (hit, _) => started.add(hit),
        onLongPressEnd: (_, _) {},
        delay: (hit, kind) =>
            kind == PointerDeviceKind.mouse ? Duration.zero : null,
      );
      final gesture = await mouse(tester);

      await gesture.down(_first);
      await tester.pump(Duration.zero);

      expect(started.single.index, 0);
      await gesture.up();
    });

    testWidgets('a click that lifts at once stays a tap', (tester) async {
      var taps = 0;
      var started = 0;
      await pumpViewport(
        tester,
        onLeafTap: (_) => taps++,
        onLongPressStart: (_, _) => started++,
        onLongPressEnd: (_, _) {},
        delay: (hit, kind) => Duration.zero,
      );
      final gesture = await mouse(tester);

      await gesture.down(_first);
      await gesture.up();
      await tester.pump();

      expect(taps, 1);
      expect(started, 0);
    });

    testWidgets('a touch press keeps the platform timing', (tester) async {
      var started = 0;
      await pumpViewport(
        tester,
        onLeafTap: (_) {},
        onLongPressStart: (_, _) => started++,
        onLongPressEnd: (_, _) {},
        delay: (hit, kind) =>
            kind == PointerDeviceKind.mouse ? Duration.zero : null,
      );

      final touch = await tester.startGesture(_first);
      await tester.pump(kLongPressTimeout - const Duration(milliseconds: 50));
      expect(started, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(started, 1);
      await touch.up();
    });

    testWidgets(
      'a mouse delay of 500 ms waits for it, and a quick click taps',
      (tester) async {
        var taps = 0;
        var started = 0;
        await pumpViewport(
          tester,
          onLeafTap: (_) => taps++,
          onLongPressStart: (_, _) => started++,
          onLongPressEnd: (_, _) {},
          delay: (hit, kind) => const Duration(milliseconds: 200),
        );
        final gesture = await mouse(tester);

        await gesture.down(_first);
        await tester.pump(const Duration(milliseconds: 150));
        expect(started, 0);
        await tester.pump(const Duration(milliseconds: 100));
        expect(started, 1);
        await gesture.up();
        await tester.pump();

        await gesture.down(_second);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pump();
        expect(taps, 1);
        expect(started, 1);
      },
    );

    testWidgets('the delay is asked per cell', (tester) async {
      var started = 0;
      await pumpViewport(
        tester,
        onLeafTap: (_) {},
        onLongPressStart: (_, _) => started++,
        onLongPressEnd: (_, _) {},
        delay: (hit, kind) => hit.index == 0 ? Duration.zero : null,
      );
      final gesture = await mouse(tester);

      await gesture.down(_second);
      await tester.pump(const Duration(milliseconds: 100));
      expect(started, 0, reason: 'the second cell keeps the platform delay');
      await gesture.up();
      await tester.pump();

      await gesture.down(_first);
      await tester.pump(Duration.zero);
      expect(started, 1);
      await gesture.up();
    });
  });

  group('geometry for a surface opened over a cell', () {
    testWidgets('the controller reports the cell and the viewport globally', (
      tester,
    ) async {
      await pumpViewport(tester, onLeafTap: (_) {});
      final hit = CatalogLeafHit(
        sectionId: 'a',
        index: 5,
        leaf: CatalogLeaf.unicode(_glyph(5)),
      );

      // Column 1 of the second row (rows start under the 24 px header).
      expect(controller.leafBoundsOf(hit), const Rect.fromLTWH(80, 64, 80, 40));
      expect(controller.viewportBounds, const Rect.fromLTWH(0, 0, 320, 480));
    });

    testWidgets('follows the scroll offset', (tester) async {
      await pumpViewport(tester, onLeafTap: (_) {});
      controller.jumpTo(30);
      await tester.pump();
      final hit = CatalogLeafHit(
        sectionId: 'a',
        index: 5,
        leaf: CatalogLeaf.unicode(_glyph(5)),
      );

      expect(controller.leafBoundsOf(hit)?.top, 34);
    });

    testWidgets('is null for a cell that is not there', (tester) async {
      await pumpViewport(tester, onLeafTap: (_) {});
      final nowhere = CatalogLeafHit(
        sectionId: 'missing',
        index: 0,
        leaf: CatalogLeaf.unicode(_glyph(0)),
      );

      expect(controller.leafBoundsOf(nowhere), isNull);
    });

    testWidgets('is null while no viewport is attached', (tester) async {
      expect(controller.viewportBounds, isNull);
    });
  });

  group('pinned leaf', () {
    Rect? washOf(WidgetTester tester) {
      final canvas = RecordingCanvas();
      render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
      final washes = [
        for (final r in canvas.rrects)
          if (r.color.toARGB32() == _hover.toARGB32()) r.rrect.outerRect,
      ];
      return washes.isEmpty ? null : washes.single;
    }

    CatalogLeafHit hitOf(int index) => CatalogLeafHit(
      sectionId: 'a',
      index: index,
      leaf: CatalogLeaf.unicode(_glyph(index)),
    );

    testWidgets('keeps the wash on the pinned cell while the mouse moves on', (
      tester,
    ) async {
      await pumpViewport(tester, onLeafTap: (_) {}, pinnedLeaf: hitOf(0));
      final gesture = await mouse(tester);

      await gesture.moveTo(_second);
      await tester.pump();

      expect(washOf(tester), const Rect.fromLTWH(0, 24, 80, 40).deflate(2));
    });

    testWidgets('paints the wash on the pinned cell with the mouse elsewhere', (
      tester,
    ) async {
      await pumpViewport(tester, onLeafTap: (_) {}, pinnedLeaf: hitOf(1));

      expect(washOf(tester), const Rect.fromLTWH(80, 24, 80, 40).deflate(2));
    });

    testWidgets('releasing the pin gives the wash back to the mouse', (
      tester,
    ) async {
      await pumpViewport(tester, onLeafTap: (_) {}, pinnedLeaf: hitOf(0));
      final gesture = await mouse(tester);
      await gesture.moveTo(_second);
      await tester.pump();

      await pumpViewport(tester, onLeafTap: (_) {});

      expect(washOf(tester), const Rect.fromLTWH(80, 24, 80, 40).deflate(2));
    });

    testWidgets('ignores the wheel while pinned and scrolls again after', (
      tester,
    ) async {
      await pumpViewport(tester, onLeafTap: (_) {}, pinnedLeaf: hitOf(0));
      final gesture = await mouse(tester);
      await gesture.moveTo(_second);
      final wheel = TestPointer(9, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(_second));

      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(controller.offset, 0);

      await pumpViewport(tester, onLeafTap: (_) {});
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(controller.offset, greaterThan(0));
    });
  });
}
