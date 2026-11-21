/// The catalogue as a fast scroll target: its controller read and moved as
/// a fraction, against the target contract and the real viewport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:viewport_scroll/testing.dart';

import 'support/asset_scopes.dart';

Future<PanelCatalogController> _pumpCatalog(WidgetTester tester) async {
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
  await tester.pump();
  return controller;
}

void main() {
  FastScrollTargetContract.run((tester) async {
    final controller = await _pumpCatalog(tester);
    final target = PanelCatalogFastScrollTarget(controller);
    return FastScrollTargetHarness(target: target, settle: tester.pump);
  });

  testWidgets('stop ends a fling where it is', (tester) async {
    final controller = await _pumpCatalog(tester);
    final target = PanelCatalogFastScrollTarget(controller);
    await tester.fling(
      find.byType(PanelCatalogViewport),
      const Offset(0, -300),
      2000,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    target.stop();
    final stopped = controller.offset;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, stopped);
  });

  testWidgets('equal on one controller, so a rebuilt one keeps listeners', (
    tester,
  ) async {
    final controller = PanelCatalogController();
    addTearDown(controller.dispose);
    expect(
      PanelCatalogFastScrollTarget(controller),
      PanelCatalogFastScrollTarget(controller),
    );
  });
}
