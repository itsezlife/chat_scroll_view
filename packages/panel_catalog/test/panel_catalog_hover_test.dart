/// The hover highlight: a mouse over a leaf paints the theme's hover token on
/// the cell, and nothing paints for a finger or for a theme without the token.
///
/// **Seam:** [PanelCatalogViewport] under a mouse (and a touch) pointer with a
/// theme that does or does not carry [PanelCatalogThemeData.leafHoverHighlightColor],
/// observed through what the viewport asks a recording canvas to draw and
/// whether it asks to be repainted.
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

  PanelCatalogThemeData withHover({double radius = 8, double inset = 2}) =>
      PanelCatalogThemeData.light.copyWith(
        leafHoverHighlightColor: _hover,
        leafHoverHighlightRadius: radius,
        leafHoverHighlightInset: inset,
      );

  Future<void> pumpViewport(
    WidgetTester tester, {
    PanelCatalogThemeData theme = PanelCatalogThemeData.light,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: theme,
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
              onLeafTap: (hit) {},
            ),
          ),
        ),
      ),
    ),
  );

  RenderPanelCatalog render(WidgetTester tester) => tester
      .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport));

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(position);
    await tester.pump();
    return mouse;
  }

  // The cell of row 0, column 1, under the header.
  const cell = Rect.fromLTWH(80, 24, 80, 40);
  const inCell = Offset(120, 44);

  List<RRect> hoverRects(RecordingCanvas canvas) => [
    for (final r in canvas.rrects)
      if (r.color.toARGB32() == _hover.toARGB32()) r.rrect,
  ];

  group('with a hover token', () {
    testWidgets('a mouse over a leaf paints the cell, inset, rounded, once', (
      tester,
    ) async {
      await pumpViewport(tester, theme: withHover());
      await mouseAt(tester, inCell);

      final rects = hoverRects(paintOnce(tester));

      expect(rects, hasLength(1));
      expect(rects.single.outerRect, cell.deflate(2));
      expect(rects.single.tlRadius, const Radius.circular(8));
    });

    testWidgets('moving to another cell moves the highlight, at once', (
      tester,
    ) async {
      await pumpViewport(tester, theme: withHover());
      final mouse = await mouseAt(tester, inCell);

      await mouse.moveTo(const Offset(200, 44));
      await tester.pump();

      expect(
        hoverRects(paintOnce(tester)).single.outerRect,
        const Rect.fromLTWH(160, 24, 80, 40).deflate(2),
      );
    });

    testWidgets('asks for a repaint when the cell under the mouse changes', (
      tester,
    ) async {
      await pumpViewport(tester, theme: withHover());
      final mouse = await mouseAt(tester, inCell);
      await tester.pump();
      expect(render(tester).debugNeedsPaint, isFalse);

      await mouse.moveTo(const Offset(200, 44));

      expect(render(tester).debugNeedsPaint, isTrue);
    });

    testWidgets('a move inside the same cell asks for nothing', (tester) async {
      await pumpViewport(tester, theme: withHover());
      final mouse = await mouseAt(tester, inCell);
      await tester.pump();

      await mouse.moveTo(const Offset(125, 50));

      expect(render(tester).debugNeedsPaint, isFalse);
    });

    testWidgets('over the header there is no highlight', (tester) async {
      await pumpViewport(tester, theme: withHover());
      await mouseAt(tester, const Offset(120, 10));

      expect(hoverRects(paintOnce(tester)), isEmpty);
    });

    testWidgets('the mouse leaving takes it away', (tester) async {
      await pumpViewport(tester, theme: withHover());
      final mouse = await mouseAt(tester, inCell);
      expect(hoverRects(paintOnce(tester)), hasLength(1));

      await mouse.moveTo(const Offset(600, 300));
      await tester.pump();

      expect(hoverRects(paintOnce(tester)), isEmpty);
    });

    testWidgets('scrolling under a still mouse moves it to the cell that '
        'arrives', (tester) async {
      await pumpViewport(tester, theme: withHover());
      await mouseAt(tester, inCell);

      controller.jumpTo(20);
      await tester.pump();

      // The pointer, at content y 64, is now over the first cell of the second
      // row, which is drawn from y 44.
      expect(
        hoverRects(paintOnce(tester)).single.outerRect,
        const Rect.fromLTWH(80, 44, 80, 40).deflate(2),
      );
    });

    testWidgets('a mouse that was there before the viewport shows the wash '
        'without moving', (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: inCell);
      addTearDown(mouse.removePointer);

      await pumpViewport(tester, theme: withHover());
      await tester.pump();

      expect(hoverRects(paintOnce(tester)), hasLength(1));
    });

    testWidgets('a finger paints none', (tester) async {
      await pumpViewport(tester, theme: withHover());

      final touch = await tester.startGesture(inCell);
      await tester.pump();

      expect(hoverRects(paintOnce(tester)), isEmpty);
      await touch.up();
    });
  });

  group('the reference desktop client\'s ink', () {
    const press = Color(0x0F000000);
    PanelCatalogThemeData desktop() => withHover().copyWith(
      leafHoverHighlightSize: const Size(34, 32),
      leafPressHighlightColor: press,
      leafPressFeedback: CatalogPressFeedback.none,
    );

    testWidgets('a hovered cell gets a 34 x 32 box of radius 8, centred, '
        'whatever the cell', (tester) async {
      await pumpViewport(tester, theme: desktop());
      await mouseAt(tester, inCell);

      final rects = hoverRects(paintOnce(tester));

      expect(rects.single.outerRect, Rect.fromCenter(
        center: cell.center,
        width: 34,
        height: 32,
      ));
      expect(rects.single.tlRadius, const Radius.circular(8));
    });

    testWidgets('a press paints no ink and does not shrink the glyph; the box '
        'stays on the pressed cell', (tester) async {
      await pumpViewport(tester, theme: desktop());
      final mouse = await mouseAt(tester, inCell);

      await mouse.down(inCell);
      await tester.pump(const Duration(milliseconds: 100));
      final canvas = paintOnce(tester);

      expect(
        canvas.rrects.where((r) => r.color.toARGB32() == press.toARGB32()),
        isEmpty,
      );
      expect(canvas.scaleCalls.where((s) => s != 1), isEmpty);
      expect(hoverRects(canvas), hasLength(1));
      await mouse.up();
    });

    testWidgets('a finger keeps the ink and the shrink', (tester) async {
      await pumpViewport(
        tester,
        theme: desktop().copyWith(
          leafPressFeedback: CatalogPressFeedback.inkAndScale,
        ),
      );
      final finger = await tester.startGesture(inCell);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        paintOnce(tester).rrects.where(
          (r) => r.color.a > 0 && r.color.toARGB32() != _hover.toARGB32(),
        ),
        isNotEmpty,
      );
      await finger.up();
    });
  });

  group('without one', () {
    testWidgets('a mouse paints nothing', (tester) async {
      await pumpViewport(tester);
      await mouseAt(tester, inCell);

      expect(paintOnce(tester).rrects, isEmpty);
    });
  });
}
