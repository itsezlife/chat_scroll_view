/// The position contract against its fake and against the real viewport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

void main() {
  group('FakeCatalogScrollPosition', () {
    runCatalogScrollPositionContract((tester) async {
      final fake = FakeCatalogScrollPosition();
      return CatalogScrollPositionHarness(
        position: fake,
        sectionCount: fake.sectionCount,
        settle: () async => fake.completeMotion(),
      );
    });
  });

  group('RenderPanelCatalog', () {
    runCatalogScrollPositionContract((tester) async {
      final snapshots = FakeCatalogSnapshotSource(
        sections: [
          for (var s = 0; s < 6; s++)
            CatalogSection(
              id: 's$s',
              title: 's$s',
              leaves: [
                for (var i = 0; i < 40; i++)
                  CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
              ],
            ),
        ],
      );
      final controller = PanelCatalogController();
      addTearDown(() {
        snapshots.dispose();
        controller.dispose();
      });
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
                ),
              ),
            ),
          ),
        ),
      );
      return CatalogScrollPositionHarness(
        position: tester.renderObject<RenderPanelCatalog>(
          find.byType(PanelCatalogViewport),
        ),
        sectionCount: 6,
        settle: () async {
          await tester.pumpAndSettle();
        },
      );
    });
  });
}
