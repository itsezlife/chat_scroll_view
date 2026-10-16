/// Roving focus on the controller: which leaf holds it, how it moves across
/// leaves and sections, what activating it does, and how it paints.
///
/// **Seam:** [PanelCatalogController] with a [PanelCatalogViewport] attached,
/// observed through the controller's answers and events, the shell callbacks,
/// the offset it scrolls to, the semantics node of the leaf and what the
/// viewport asks its canvas to draw (a recording canvas passed to `paint`).
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';
import 'support/recording_canvas.dart';
import 'support/semantics_support.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480 viewport:
// rows 0..10 are fully in view at offset 0, row 11 is cut at 504.
const _span = 4;
const _viewportHeight = 480.0;

String _glyph(int i) => String.fromCharCode(0x1F600 + i % 80);

CatalogSection _section(String id, int count) => CatalogSection(
  id: id,
  title: 'Title $id',
  leaves: [for (var i = 0; i < count; i++) CatalogLeaf.unicode(_glyph(i))],
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<CatalogLeafHit> taps;
  late List<PanelCatalogFocusChanged> focusEvents;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    taps = [];
    focusEvents = [];
    controller.events.listen((event) {
      if (event is PanelCatalogFocusChanged) focusEvents.add(event);
    });
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    PanelCatalogThemeData theme = PanelCatalogThemeData.light,
    bool wired = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: PanelCatalogTheme(
          data: theme,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: _viewportHeight,
                child: PanelCatalogViewport(
                  snapshots: snapshots,
                  assets: textGlyphScope(),
                  controller: controller,
                  spanCount: _span,
                  cellExtent: 40,
                  headerExtent: 24,
                  onLeafTap: wired ? taps.add : null,
                ),
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

  void expectFocus(String sectionId, int index) {
    final hit = controller.focusedLeaf;
    expect(hit?.sectionId, sectionId, reason: 'section of the focused leaf');
    expect(hit?.index, index, reason: 'index of the focused leaf');
  }

  group('without a viewport', () {
    test('there is nothing to focus, move or activate', () {
      expect(controller.focusedLeaf, isNull);
      expect(controller.focusLeaf('a', 0), isFalse);
      expect(controller.moveFocus(CatalogFocusMove.next), isFalse);
      expect(controller.activateFocusedLeaf(), isFalse);
      controller.clearFocus();
      expect(focusEvents, isEmpty);
    });
  });

  group('focusing a leaf', () {
    testWidgets('names it, tells the listeners and is the hit of the cell', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 12), _section('b', 12)]);
      await pumpViewport(tester);

      expect(controller.focusLeaf('b', 5), isTrue);

      expectFocus('b', 5);
      expect(
        controller.focusedLeaf!.leaf,
        snapshots.value.sections[1].leaves[5],
      );
      expect(focusEvents.single.leaf, controller.focusedLeaf);
    });

    testWidgets('a cell that does not exist is refused and changes nothing', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 1);
      focusEvents.clear();

      expect(controller.focusLeaf('nope', 0), isFalse);
      expect(controller.focusLeaf('a', 12), isFalse);
      expect(controller.focusLeaf('a', -1), isFalse);

      expectFocus('a', 1);
      expect(focusEvents, isEmpty);
    });

    testWidgets('the same cell again is silent', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 1);

      expect(controller.focusLeaf('a', 1), isTrue);

      expect(focusEvents, hasLength(1));
    });

    testWidgets('scrolls a cell out of view in', (tester) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);

      controller.focusLeaf('a', 200);

      // Row 50 starts at 24 + 50 * 40 and ends 40 below.
      expect(controller.offset, 24 + 50 * 40 + 40 - _viewportHeight);
    });

    testWidgets('leaves the offset alone when the cell is in view', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);

      controller.focusLeaf('a', 9);

      expect(controller.offset, 0);
    });

    testWidgets('without reveal it does not scroll', (tester) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);

      controller.focusLeaf('a', 200, reveal: false);

      expectFocus('a', 200);
      expect(controller.offset, 0);
    });

    testWidgets('can be cleared', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 1);

      controller.clearFocus();

      expect(controller.focusedLeaf, isNull);
      expect(focusEvents.last.leaf, isNull);
    });
  });

  group('moving focus', () {
    testWidgets('from nowhere it enters at the first leaf in view', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);
      controller.jumpTo(24 + 10 * 40);

      expect(controller.moveFocus(CatalogFocusMove.down), isTrue);

      expectFocus('a', 40);
      expect(controller.offset, 24 + 10 * 40, reason: 'already in view');
    });

    testWidgets('enters at the start of the catalog when it is in view', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);

      controller.moveFocus(CatalogFocusMove.right);

      expectFocus('a', 0);
    });

    testWidgets('first and last go to the ends of the catalog', (tester) async {
      snapshots.replaceSections([_section('a', 12), _section('b', 7)]);
      await pumpViewport(tester);

      controller.moveFocus(CatalogFocusMove.last);
      expectFocus('b', 6);

      controller.moveFocus(CatalogFocusMove.first);
      expectFocus('a', 0);
    });

    testWidgets('arrows move one cell on screen', (tester) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 5);

      controller.moveFocus(CatalogFocusMove.right);
      expectFocus('a', 6);
      controller.moveFocus(CatalogFocusMove.down);
      expectFocus('a', 10);
      controller.moveFocus(CatalogFocusMove.left);
      expectFocus('a', 9);
      controller.moveFocus(CatalogFocusMove.up);
      expectFocus('a', 5);
    });

    testWidgets('the end of the catalog refuses and keeps the focus', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 6)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 5);
      focusEvents.clear();

      expect(controller.moveFocus(CatalogFocusMove.next), isFalse);
      expect(controller.moveFocus(CatalogFocusMove.down), isFalse);

      expectFocus('a', 5);
      expect(focusEvents, isEmpty);
    });

    testWidgets('scrolls the cell it lands on into view', (tester) async {
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 40);
      expect(controller.offset, 0);

      controller.moveFocus(CatalogFocusMove.down);

      // Row 11 ends at 24 + 12 * 40 = 504.
      expect(controller.offset, 504 - _viewportHeight);
      controller.moveFocus(CatalogFocusMove.up);
      expect(controller.offset, 504 - _viewportHeight, reason: 'in view');
    });

    testWidgets('crosses into the next section and brings its header', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 80), _section('b', 8)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 79);
      // Row 19 of a ends at 24 + 20 * 40 = 824.
      expect(controller.offset, 824 - _viewportHeight);

      expect(controller.moveFocus(CatalogFocusMove.next), isTrue);

      expectFocus('b', 0);
      // b's header starts at 824; its first row ends at 824 + 24 + 40.
      expect(controller.offset, 824 + 24 + 40 - _viewportHeight);
    });

    testWidgets('steps over a section with nothing in it', (tester) async {
      snapshots.replaceSections([
        _section('a', 4),
        _section('empty', 0),
        _section('b', 4),
      ]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 3);

      controller.moveFocus(CatalogFocusMove.next);

      expectFocus('b', 0);
    });

    testWidgets('in a right-to-left grid left is the next leaf', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester, direction: TextDirection.rtl);
      controller.focusLeaf('a', 1);

      controller.moveFocus(CatalogFocusMove.left);
      expectFocus('a', 2);
      controller.moveFocus(CatalogFocusMove.right);
      controller.moveFocus(CatalogFocusMove.right);
      expectFocus('a', 0);
    });
  });

  group('activating', () {
    testWidgets('emits the hit a tap on the cell emits', (tester) async {
      snapshots.replaceSections([_section('a', 12), _section('b', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('b', 5);
      final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));

      expect(controller.activateFocusedLeaf(), isTrue);
      // b: header at 24 + 3 * 40 = 144, rows from 168; leaf 5 is row 1, col 1.
      await tester.tapAt(origin + const Offset(120, 168 + 40 + 20));

      expect(taps, hasLength(2));
      expect(taps[0], taps[1]);
      expect(taps[0].leaf, taps[1].leaf);
      expect(taps[0].sectionId, 'b');
      expect(taps[0].index, 5);
    });

    testWidgets('does nothing without focus or without a shell tap', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      expect(controller.activateFocusedLeaf(), isFalse);

      await pumpViewport(tester, wired: false);
      controller.focusLeaf('a', 0);
      expect(controller.activateFocusedLeaf(), isFalse);
      expect(taps, isEmpty);
    });
  });

  group('when the catalog changes', () {
    testWidgets('a focused leaf that stays keeps focus, with its new value', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 2);
      focusEvents.clear();

      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [
            for (var i = 0; i < 12; i++)
              CatalogLeaf.unicode(_glyph(i), spokenName: 'name $i'),
          ],
        ),
      ]);
      await tester.pump();

      expectFocus('a', 2);
      expect(controller.focusedLeaf!.leaf.spokenName, 'name 2');
      expect(focusEvents, isEmpty);
    });

    testWidgets('a section that goes takes the focus with it', (tester) async {
      snapshots.replaceSections([_section('a', 12), _section('b', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('b', 2);

      snapshots.replaceSections([_section('a', 12)]);
      await tester.pump();

      expect(controller.focusedLeaf, isNull);
      expect(focusEvents.last.leaf, isNull);
    });

    testWidgets('a leaf that goes takes the focus with it', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 10);

      snapshots.replaceSections([_section('a', 6)]);
      await tester.pump();

      expect(controller.focusedLeaf, isNull);
    });

    testWidgets('leaving the tree ends focus', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 2);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(controller.focusedLeaf, isNull);
    });
  });

  group('painting', () {
    // Cell (a, 1): column 1 of row 0, under the 24 px header.
    const cell = Rect.fromLTWH(80, 24, 80, 40);
    const press = Color(0x0F000000);

    bool highlighted(RecordingCanvas canvas, Color color) => canvas.rrects.any(
      (r) =>
          r.rrect.outerRect == cell && r.color.toARGB32() == color.toARGB32(),
    );

    testWidgets('the focused cell gets the press highlight, at full alpha', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      expect(highlighted(paintOnce(tester), press), isFalse);

      controller.focusLeaf('a', 1);
      await tester.pump();

      expect(highlighted(paintOnce(tester), press), isTrue);
      expect(paintOnce(tester).rrects, hasLength(1), reason: 'one cell only');
    });

    testWidgets('a focus token of its own is used instead', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      const focus = Color(0x33336699);
      await pumpViewport(
        tester,
        theme: PanelCatalogThemeData.light.copyWith(
          leafPressHighlightColor: const Color(0x00000000),
          leafFocusHighlightColor: focus,
        ),
      );

      controller.focusLeaf('a', 1);
      await tester.pump();

      expect(highlighted(paintOnce(tester), focus), isTrue);
    });

    testWidgets('a cleared focus paints no highlight', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 1);
      await tester.pump();

      controller.clearFocus();
      await tester.pump();

      expect(paintOnce(tester).rrects, isEmpty);
    });

    testWidgets('moving focus repaints', (tester) async {
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 0);
      await tester.pump();
      final before = tester
          .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
          .debugNeedsPaint;
      expect(before, isFalse);

      controller.moveFocus(CatalogFocusMove.right);

      expect(
        tester
            .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
            .debugNeedsPaint,
        isTrue,
      );
    });
  });

  group('for a screen reader', () {
    testWidgets('the focused leaf reports focus', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);
      controller.focusLeaf('a', 1);
      await tester.pump();

      SemanticsNode node(int i) => viewportNodeLabelled(tester, _glyph(i));

      expect(
        node(1).getSemanticsData().flagsCollection.isFocused,
        Tristate.isTrue,
      );
      expect(
        node(2).getSemanticsData().flagsCollection.isFocused,
        Tristate.isFalse,
      );
      handle.dispose();
    });

    testWidgets('asking a leaf node for focus moves roving focus there', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 12)]);
      await pumpViewport(tester);

      performSemanticsAction(
        tester,
        viewportNodeLabelled(tester, _glyph(6)),
        SemanticsAction.focus,
      );

      expectFocus('a', 6);
      handle.dispose();
    });
  });
}
