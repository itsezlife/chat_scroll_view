/// The remove badge: the cell under a mouse that the host says can be
/// removed draws a cross at its top end corner over its content, and a click
/// on the cross removes it instead of picking it.
///
/// **Seam:** [PanelCatalogViewport] under a mouse (and a touch) pointer, with
/// `leafRemovable` true for the even cells, observed through what the
/// viewport asks a recording canvas to draw, the badge's box it reports, and
/// the taps and removals it calls back.
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
String _glyph(int i) => String.fromCharCode(0x1F600 + i % 80);

CatalogSection _section(String id, int count) => CatalogSection(
  id: id,
  title: 'Title $id',
  leaves: [for (var i = 0; i < count; i++) CatalogLeaf.unicode(_glyph(i))],
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<int> taps;
  late List<int> removed;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource(sections: [_section('a', 40)]);
    controller = PanelCatalogController();
    taps = [];
    removed = [];
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    CatalogLeafRemoveBadge badge = CatalogLeafRemoveBadge.pointer,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: PanelCatalogThemeData.light,
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
              onLeafTap: (hit) => taps.add(hit.index),
              leafRemovable: (hit) => hit.index.isEven,
              onLeafRemove: (hit) => removed.add(hit.index),
              removeBadge: badge,
            ),
          ),
        ),
      ),
    ),
  );

  RenderPanelCatalog render(WidgetTester tester) => tester
      .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport));

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(position);
    await tester.pump();
    return mouse;
  }

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  // Cell 0 (removable) and cell 1 (not), row 0, under the header.
  const first = Rect.fromLTWH(0, 24, 80, 40);
  const second = Rect.fromLTWH(80, 24, 80, 40);
  final onBadge = first.topRight + const Offset(-5, 5);

  testWidgets('a mouse on a removable cell shows a 14 px badge flush with '
      'its top right corner, drawn last', (tester) async {
    await pumpViewport(tester);
    await mouseAt(tester, first.center);

    final box = render(tester).debugRemoveBadgeRect;
    expect(box, Rect.fromLTWH(first.right - 14, first.top, 14, 14));

    final badge = paintOnce(tester).rrects.last;
    expect(badge.rrect.outerRect, box);
    expect(badge.color.a, closeTo(0.3, 0.01));
  });

  testWidgets('a cell the host keeps shows none', (tester) async {
    await pumpViewport(tester);
    await mouseAt(tester, second.center);

    expect(render(tester).debugRemoveBadgeRect, isNull);
  });

  testWidgets('a click on the badge removes the cell and does not pick it; '
      'a click elsewhere on the cell picks it', (tester) async {
    await pumpViewport(tester);
    final mouse = await mouseAt(tester, onBadge);

    await mouse.down(onBadge);
    await mouse.up();
    await tester.pump();
    expect(removed, [0]);
    expect(taps, isEmpty);

    await mouse.moveTo(first.center);
    await tester.pump();
    await mouse.down(first.center);
    await mouse.up();
    await tester.pump();
    expect(removed, [0]);
    expect(taps, [0]);
  });

  testWidgets('the badge darkens while the mouse is on it', (tester) async {
    await pumpViewport(tester);
    await mouseAt(tester, onBadge);

    expect(paintOnce(tester).rrects.last.color.a, closeTo(0.5, 0.01));
  });

  testWidgets('a finger shows no badge and its tap picks', (tester) async {
    await pumpViewport(tester);
    await tester.tapAt(onBadge);
    await tester.pump();

    expect(render(tester).debugRemoveBadgeRect, isNull);
    expect(taps, [0]);
    expect(removed, isEmpty);
  });

  testWidgets('the web look is a 16 px circle 2 px past the corner', (
    tester,
  ) async {
    await pumpViewport(tester, badge: CatalogLeafRemoveBadge.web);
    await mouseAt(tester, first.center);

    expect(
      render(tester).debugRemoveBadgeRect,
      Rect.fromLTWH(first.right + 2 - 16, first.top - 2, 16, 16),
    );
  });
}
