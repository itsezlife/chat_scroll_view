/// A right-to-left catalog: where cells and header parts sit, what a pointer
/// hits, and where a section jump lands.
///
/// **Seam:** [PanelCatalogViewport] under a `Directionality`, driven with
/// [FakeCatalogSnapshotSource] and a text-glyph scope, observed through what it
/// asks its canvas to draw (a recording canvas passed to `paint`), the shell
/// callbacks and the controller's offset. Text is flutter_test's Ahem font: a
/// character is one em wide and the header style (15 px) makes the label
/// "More" 60 px.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';
import 'support/recording_canvas.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480 viewport.
// The header insets its text by 8 px at its start and the action's hit area is
// the label (60) plus 8 on each side: 76 px, at the end of the band.
const _span = 4;

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(
  String id, {
  int leaves = 8,
  CatalogSectionAction? action,
  SectionLayout? layout,
}) => CatalogSection(
  id: id,
  title: id,
  action: action,
  layout: layout,
  leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode(_glyph(i))],
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<CatalogLeafHit> taps;
  late List<(String, String)> actions;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    taps = [];
    actions = [];
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    TextDirection direction = TextDirection.rtl,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: PanelCatalogTheme(
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
                  onSectionAction: (sectionId, actionId) =>
                      actions.add((sectionId, actionId)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> tapAt(WidgetTester tester, Offset local) async {
    final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));
    await tester.tapAt(origin + local);
    await tester.pump();
  }

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    tester
        .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
        .paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  // First row of a section at the top: header 0..24, cells 24..64.
  const firstRowY = 40.0;

  group('cells', () {
    testWidgets('the first leaf is at the right edge in a right-to-left grid', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a')]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(310, firstRowY));
      await tapAt(tester, const Offset(10, firstRowY));

      expect([for (final hit in taps) hit.index], [0, 3]);
    });

    testWidgets('the first leaf is at the left edge in a left-to-right grid', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a')]);
      await pumpViewport(tester, direction: TextDirection.ltr);

      await tapAt(tester, const Offset(10, firstRowY));
      await tapAt(tester, const Offset(310, firstRowY));

      expect([for (final hit in taps) hit.index], [0, 3]);
    });

    testWidgets('a section that states its direction overrides the catalog', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section(
          'a',
          layout: const SectionLayout.grid(textDirection: TextDirection.ltr),
        ),
      ]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(10, firstRowY));

      expect(taps.single.index, 0);
    });

    testWidgets('a change of directionality moves the cells', (tester) async {
      snapshots.replaceSections([_section('a')]);
      await pumpViewport(tester, direction: TextDirection.ltr);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(310, firstRowY));

      expect(taps.single.index, 0);
    });
  });

  group('header', () {
    testWidgets('the title spans the band minus its inset at the start', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a')]);
      await pumpViewport(tester);

      final title = paintOnce(tester).paragraphDraws.first;

      // Laid out across the whole band less the 8 px start inset, ending at it.
      expect(title.offset.dx, 0);
      expect(title.width, 312);
    });

    testWidgets('the action is at the left edge, the title after it', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section(
          'a',
          action: const CatalogSectionAction(id: 'more', label: 'More'),
        ),
      ]);
      await pumpViewport(tester);

      final paragraphs = paintOnce(tester).paragraphDraws;
      final title = paragraphs[0];
      final label = paragraphs[1];

      // Hit area 0..76: the label starts after the inset.
      expect(label.offset.dx, 8);
      expect(title.offset.dx, 76);
      expect(title.width, 320 - 8 - 76);
    });

    testWidgets('the action is at the right edge left to right', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section(
          'a',
          action: const CatalogSectionAction(id: 'more', label: 'More'),
        ),
      ]);
      await pumpViewport(tester, direction: TextDirection.ltr);

      final paragraphs = paintOnce(tester).paragraphDraws;

      expect(paragraphs[1].offset.dx, 320 - 8 - 60);
      expect(paragraphs[0].offset.dx, 8);
    });

    testWidgets('a tap on the left edge reaches the action', (tester) async {
      snapshots.replaceSections([
        _section(
          'a',
          action: const CatalogSectionAction(id: 'more', label: 'More'),
        ),
      ]);
      await pumpViewport(tester);

      await tapAt(tester, const Offset(40, 12));
      await tapAt(tester, const Offset(280, 12));

      expect(actions, [('a', 'more')]);
    });
  });

  group('section jump', () {
    List<CatalogSection> many() => [
      for (var i = 0; i < 12; i++) _section('s$i', leaves: 16),
    ];

    testWidgets('lands on the offset it lands on left to right', (
      tester,
    ) async {
      snapshots.replaceSections(many());
      await pumpViewport(tester, direction: TextDirection.ltr);
      controller.jumpToSection(5).ignore();
      await tester.pumpAndSettle();
      final ltrOffset = controller.offset;

      await tester.pumpWidget(const SizedBox.shrink());
      controller.jumpTo(0);
      await pumpViewport(tester);
      controller.jumpToSection(5).ignore();
      await tester.pumpAndSettle();

      expect(controller.offset, ltrOffset);
      expect(ltrOffset, greaterThan(0));
    });

    testWidgets('the landed section starts at the right edge', (tester) async {
      snapshots.replaceSections(many());
      await pumpViewport(tester);
      controller.jumpToSection(5).ignore();
      await tester.pumpAndSettle();

      // Header lands at the top; its first row is 24 px below.
      await tapAt(tester, const Offset(310, 24 + 20));

      expect(taps.single.sectionId, 's5');
      expect(taps.single.index, 0);
    });
  });
}
