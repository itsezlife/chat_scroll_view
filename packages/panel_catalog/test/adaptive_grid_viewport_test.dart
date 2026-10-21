/// A grid that takes its column count from its width, as the reference desktop
/// client's emoji list does: as many columns of at least the desired width as
/// fit, each a whole number of pixels wide, the row a fixed amount shorter
/// than the cell is wide, and what the integer division leaves split on both
/// sides.
///
/// **Seam:** [PanelCatalogViewport] with one section of
/// `SectionLayout.grid(desiredCellWidth:, cellHeightInset:)`, observed through
/// the leaf a tap lands on. The expected numbers are the reference client's
/// own (its selector of width W gives the list W - 12 for its columns, which
/// the 8 px left and 4 px right padding reproduce here).
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

const _header = 20.0;
const _padding = EdgeInsets.only(left: 8, right: 4);
const _layout = SectionLayout.grid(
  desiredCellWidth: 37,
  cellHeightInset: 2,
  headerExtent: _header,
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late AssetCacheScope assets;
  late PanelCatalogController controller;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource()
      ..replaceSections([
        CatalogSection(
          id: 'a',
          title: 'a',
          layout: _layout,
          leaves: [
            for (var i = 0; i < 40; i++)
              CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
          ],
        ),
      ]);
    assets = textGlyphScope();
    controller = PanelCatalogController();
    addTearDown(() {
      snapshots.dispose();
      controller.dispose();
    });
  });

  Future<List<int>> tapped(WidgetTester tester, double width) async {
    final hits = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: PanelCatalogThemeData.light,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 400,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: assets,
                controller: controller,
                padding: _padding,
                onLeafTap: (hit) => hits.add(hit.index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return hits;
  }

  // Selector width W: columns, cell width, cell height, the left share of the
  // integer remainder.
  for (final (width, columns, cellWidth, cellHeight, left) in [
    (292.0, 7, 40.0, 38.0, 0.0),
    (320.0, 8, 38.0, 36.0, 2.0),
    (345.0, 9, 37.0, 35.0, 0.0),
    (360.0, 9, 38.0, 36.0, 3.0),
    (392.0, 10, 38.0, 36.0, 0.0),
  ]) {
    testWidgets('$width wide: $columns columns of $cellWidth x $cellHeight', (
      tester,
    ) async {
      final hits = await tapped(tester, width);
      final x0 = _padding.left + left;

      // The last column of the first row.
      await tester.tapAt(
        Offset(x0 + (columns - 0.5) * cellWidth, _header + cellHeight / 2),
      );
      // The first column of the second row.
      await tester.tapAt(
        Offset(x0 + cellWidth / 2, _header + cellHeight * 1.5),
      );
      // Just inside the second column, a pixel past the first one's edge.
      await tester.tapAt(Offset(x0 + cellWidth + 1, _header + 2));
      await tester.pump(const Duration(milliseconds: 500));

      expect(hits, [columns - 1, columns, 1]);
    });
  }
}
