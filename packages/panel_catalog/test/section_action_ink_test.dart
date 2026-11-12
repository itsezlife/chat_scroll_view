/// The ink of a section header's painted action under a mouse: a hover fill
/// in the circle its icon sits in, and a ripple from a press that grows over
/// 650 ms and fades over 200 ms once released.
///
/// **Seam:** [PanelCatalogViewport] under a theme with a hover wash (the
/// pointer arrangement's), one section whose header carries a painted
/// action, observed through the ink the render object reports and what it
/// asks a recording canvas to draw.
library;

import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_action_ink.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480 viewport;
// the header's action icon is a 24 px box at its end, 8 px in.
const _hover = Color(0x14000000);
const _press = Color(0x0F000000);

void _paintIcon(Canvas canvas, Rect box, Color color) =>
    canvas.drawRect(box.deflate(6), Paint()..color = color);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<(String, String)> actions;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource(
      sections: [
        CatalogSection(
          id: 'a',
          title: 'a',
          action: const CatalogSectionAction(
            id: 'tone',
            painter: _paintIcon,
            semanticLabel: 'Tone',
          ),
          leaves: [
            for (var i = 0; i < 8; i++)
              CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
          ],
        ),
      ],
    );
    controller = PanelCatalogController();
    actions = [];
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(WidgetTester tester, {bool hover = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: PanelCatalogTheme(
            data: PanelCatalogThemeData.light.copyWith(
              leafHoverHighlightColor: hover ? _hover : null,
              leafPressHighlightColor: _press,
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
                  onLeafTap: (_) {},
                  onSectionAction: (section, action) =>
                      actions.add((section, action)),
                ),
              ),
            ),
          ),
        ),
      );

  RenderPanelCatalog render(WidgetTester tester) => tester
      .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport));

  // The action's icon box: the 24 px square at the header's end.
  Rect icon(WidgetTester tester) {
    final inset = PanelCatalogThemeData.light.sectionHeaderStartInset;
    return Rect.fromLTWH(
      320 - inset - CatalogSectionAction.iconExtent,
      0,
      CatalogSectionAction.iconExtent,
      24,
    );
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(position);
    await tester.pump();
    return mouse;
  }

  testWidgets('a mouse over the action fills its circle with the hover wash', (
    tester,
  ) async {
    await pumpViewport(tester);
    final at = icon(tester).center;
    await mouseAt(tester, at);

    expect(render(tester).debugHoveredAction, 'a');
  });

  testWidgets('a press grows a ripple over 650 ms and a release fades it '
      'over 200 ms; the action is still reported', (tester) async {
    await pumpViewport(tester);
    final at = icon(tester).center;
    final mouse = await mouseAt(tester, at);

    await mouse.down(at);
    await tester.pump();
    await tester.pump(CatalogActionInk.grow ~/ 2);
    final half = render(tester).debugActionPress;
    expect(half?.sectionId, 'a');
    expect(half!.grown, greaterThan(0.5));
    expect(half.grown, lessThan(1));
    expect(half.alpha, 1);

    await mouse.up();
    await tester.pump();
    await tester.pump(CatalogActionInk.fade ~/ 2);
    expect(render(tester).debugActionPress!.alpha, closeTo(0.5, 0.05));
    await tester.pump(CatalogActionInk.fade);
    expect(render(tester).debugActionPress, isNull);
    expect(actions, [('a', 'tone')]);
  });

  testWidgets('a secondary click draws no ripple', (tester) async {
    await pumpViewport(tester);
    final at = icon(tester).center;
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(at);
    await tester.pump(const Duration(milliseconds: 100));

    expect(render(tester).debugActionPress, isNull);
    await mouse.up();
  });

  testWidgets('a theme with no hover wash (touch) has no ink', (tester) async {
    await pumpViewport(tester, hover: false);
    final at = icon(tester).center;
    final mouse = await mouseAt(tester, at);
    await mouse.down(at);
    await tester.pump(const Duration(milliseconds: 100));

    expect(render(tester).debugHoveredAction, isNull);
    expect(render(tester).debugActionPress, isNull);
    await mouse.up();
  });
}
