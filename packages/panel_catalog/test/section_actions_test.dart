/// The trailing action of a section header: what the viewport paints for it,
/// where its hit area is, and the `onSectionAction` callback a tap reaches.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource]
/// and a text-glyph scope, observed through what it asks its canvas to draw (a
/// recording canvas passed to `paint`), the shell callbacks and the
/// controller's offset. Text is flutter_test's Ahem font, so a character is one
/// em wide and the header style (15 px) makes the label "More" 60 px.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';
import 'support/recording_canvas.dart';

// Geometry: 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480
// viewport. The header insets its text by 8 px at both ends, so the label
// "More" (60 px) has a hit area from x = 320 - 60 - 16 = 244 to the edge.
const _span = 4;

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(
  String id, {
  CatalogSectionAction? action,
  int leaves = 8,
}) => CatalogSection(
  id: id,
  title: id,
  action: action,
  leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode(_glyph(i))],
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<(String, String)> actions;
  late List<CatalogLeafHit> taps;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    actions = [];
    taps = [];
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(WidgetTester tester, {bool wired = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: PanelCatalogTheme(
            data: PanelCatalogThemeData.light,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 480,
                  child: PanelCatalogViewport(
                    snapshots: snapshots,
                    assets: textGlyphScope(),
                    controller: controller,
                    spanCount: _span,
                    cellExtent: 40,
                    headerExtent: 24,
                    onLeafTap: taps.add,
                    onSectionAction: wired
                        ? (sectionId, actionId) =>
                              actions.add((sectionId, actionId))
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    tester
        .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
        .paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  Future<void> tapAt(WidgetTester tester, Offset local) async {
    final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));
    await tester.tapAt(origin + local);
    await tester.pump();
  }

  group('what the header paints', () {
    testWidgets('a title alone is one paragraph', (tester) async {
      snapshots.replaceSections([_section('a', leaves: 0)]);
      await pumpViewport(tester);

      expect(paintOnce(tester).paragraphs, 1);
    });

    testWidgets('a label adds a paragraph', (tester) async {
      snapshots.replaceSections([
        _section(
          'a',
          leaves: 0,
          action: const CatalogSectionAction(id: 'm', label: 'M'),
        ),
      ]);
      await pumpViewport(tester);

      expect(paintOnce(tester).paragraphs, 2);
    });

    testWidgets('a label and an icon add two', (tester) async {
      snapshots.replaceSections([
        _section(
          'a',
          leaves: 0,
          action: const CatalogSectionAction(
            id: 'm',
            label: 'More',
            icon: Icons.chevron_right,
          ),
        ),
      ]);
      await pumpViewport(tester);

      expect(paintOnce(tester).paragraphs, 3);
    });

    testWidgets('an action does not change the extent', (tester) async {
      snapshots.replaceSections([
        _section(
          'a',
          action: const CatalogSectionAction(id: 'm', label: 'M'),
        ),
      ]);
      await pumpViewport(tester);

      expect(controller.contentExtent, 24 + 2 * 40);
    });
  });

  group('the hit area', () {
    const more = CatalogSectionAction(id: 'more', label: 'More');

    testWidgets('a tap on the label reports the section and the action', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', action: more)]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(290, 12));

      expect(actions, [('a', 'more')]);
    });

    testWidgets('it reaches from the label start inset to the edge', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', action: more)]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(245, 2));
      await tapAt(tester, const Offset(319, 22));

      expect(actions, [('a', 'more'), ('a', 'more')]);
    });

    testWidgets('a tap on the title or beside the action reports nothing', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', action: more)]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(20, 12));
      await tapAt(tester, const Offset(243, 12));

      expect(actions, isEmpty);
    });

    testWidgets(
      'a tap below the header band reaches the leaf, not the action',
      (tester) async {
        snapshots.replaceSections([_section('a', action: more)]);
        await pumpViewport(tester);

        await tapAt(tester, const Offset(290, 44));

        expect(actions, isEmpty);
        expect(taps.single.sectionId, 'a');
      },
    );

    testWidgets('an icon-only action is at least 48 px wide to hit', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section(
          'a',
          action: const CatalogSectionAction(id: 'add', icon: Icons.add),
        ),
      ]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(275, 12));
      await tapAt(tester, const Offset(270, 12));

      expect(actions, [('a', 'add')]);
    });

    testWidgets('it follows the header as the catalogue scrolls', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', action: more, leaves: 200)]);
      await pumpViewport(tester);

      controller.jumpTo(10);
      await tester.pump();
      // The header band now spans y -10 .. 14.
      await tapAt(tester, const Offset(290, 5));
      await tapAt(tester, const Offset(290, 20));

      expect(actions, [('a', 'more')]);
    });

    testWidgets('the tapped section is the one reported', (tester) async {
      snapshots.replaceSections([
        _section(
          'a',
          action: const CatalogSectionAction(id: 'x', label: 'X'),
        ),
        _section(
          'b',
          action: const CatalogSectionAction(id: 'y', label: 'Y'),
        ),
      ]);
      await pumpViewport(tester);

      // Section a: header 24 + 2 rows of 40 = 104, so b's header starts at 104.
      await tapAt(tester, const Offset(300, 110));

      expect(actions, [('b', 'y')]);
    });

    testWidgets('a section without an action is silent', (tester) async {
      snapshots.replaceSections([_section('a')]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(300, 12));

      expect(actions, isEmpty);
    });

    testWidgets('without a callback a tap is silent and a drag still scrolls', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', action: more, leaves: 200)]);
      await pumpViewport(tester, wired: false);

      await tapAt(tester, const Offset(290, 12));
      final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));
      await tester.dragFrom(
        origin + const Offset(290, 12),
        const Offset(0, -100),
      );
      await tester.pump();

      expect(actions, isEmpty);
      expect(controller.offset, greaterThan(0));
    });

    testWidgets(
      'a drag that starts on the action scrolls and reports nothing',
      (tester) async {
        snapshots.replaceSections([_section('a', action: more, leaves: 200)]);
        await pumpViewport(tester);

        final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));
        await tester.dragFrom(
          origin + const Offset(290, 12),
          const Offset(0, -100),
        );
        await tester.pump();

        expect(actions, isEmpty);
        expect(controller.offset, greaterThan(0));
      },
    );
  });
}
