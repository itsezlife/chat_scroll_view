/// What a section paints for each state of the collection behind it: skeleton
/// leaves while it loads or after it failed, a message row when it loaded
/// nothing, its leaves when it loaded.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource]
/// and a real [AssetCacheScope] over a [FakeAssetProducer]. What is observed is
/// what the viewport asks its canvas to draw (a recording canvas passed to
/// `paint`), the requests the producer receives, the extent the controller
/// reports and the shell callbacks, never render-object fields.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/recording_canvas.dart';

// Geometry: 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480
// viewport, so a glyph box is 28.8 and a row starts at 24 + 40 * row.
const _span = 4;
const _theme = PanelCatalogThemeData.light;
final _skeleton = _theme.skeletonColor.toARGB32();

CatalogLeaf _doc(int i) => CatalogLeaf.document(
  'doc-$i',
  semanticKind: SemanticKind.customEmoji,
  mediaForm: MediaForm.still,
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeAssetProducer producer;
  late AssetCacheScope scope;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    scope = AssetCacheScope(producer: producer);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    ValueChanged<CatalogLeafHit>? onLeafTap,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: _theme,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: scope,
                controller: controller,
                spanCount: _span,
                cellExtent: 40,
                headerExtent: 24,
                onLeafTap: onLeafTap,
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

  group('skeleton leaves', () {
    testWidgets('a loading section paints the count it asks for', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 6,
        ),
      ]);
      await pumpViewport(tester);

      final skeletons = paintOnce(
        tester,
      ).circles.where((c) => c.color.toARGB32() == _skeleton);

      expect(skeletons, hasLength(6));
    });

    testWidgets('they fill the grid row by row in the placeholder style', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 5,
        ),
      ]);
      await pumpViewport(tester);

      final centers = paintOnce(tester).circles.map((c) => c.center).toList();

      // Cells are 80 x 40; the first row starts under the 24 px header.
      expect(centers, [
        const Offset(40, 44),
        const Offset(120, 44),
        const Offset(200, 44),
        const Offset(280, 44),
        const Offset(40, 84),
      ]);
    });

    testWidgets('a section style other than the circle is honoured', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 3,
          placeholderStyle: CatalogPlaceholderStyle.thumbFirst,
        ),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.circles, isEmpty);
      expect(
        canvas.rrects.where((r) => r.color.toARGB32() == _skeleton),
        hasLength(3),
      );
    });

    testWidgets('a failed section paints them too, with no error row', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.failed,
          skeletonCount: 4,
        ),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.circles, hasLength(4));
      // The header title is the only text.
      expect(canvas.paragraphs, 1);
    });

    testWidgets('one row of the section columns is the default count', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
        ),
      ]);
      await pumpViewport(tester);

      expect(paintOnce(tester).circles, hasLength(_span));
      expect(controller.contentExtent, 24 + 40);
    });

    testWidgets('they add rows to the extent like leaves would', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 9,
        ),
      ]);
      await pumpViewport(tester);

      // 24 header + ceil(9 / 4) = 3 rows of 40.
      expect(controller.contentExtent, 24 + 3 * 40);
    });

    testWidgets('they attach nothing to the cache', (tester) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 8,
        ),
      ]);
      await pumpViewport(tester);

      expect(
        tester
            .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
            .attachedLeafCount,
        0,
      );
      expect(producer.attempts, isEmpty);
    });

    testWidgets('a tap on one is no leaf hit', (tester) async {
      final hits = <CatalogLeafHit>[];
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 8,
        ),
      ]);
      await pumpViewport(tester, onLeafTap: hits.add);

      final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));
      await tester.tapAt(origin + const Offset(40, 44));
      await tester.pump();

      expect(hits, isEmpty);
    });

    testWidgets('a section that is loading more keeps its leaves and '
        'appends the skeletons after them', (tester) async {
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [_doc(0), _doc(1), _doc(2)],
          state: CatalogSectionState.loading,
          skeletonCount: 3,
        ),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      // The three leaves hold the first row's cells but the last; skeletons
      // continue from the fourth cell.
      expect(canvas.circles.map((c) => c.center).toList(), [
        const Offset(280, 44),
        const Offset(40, 84),
        const Offset(120, 84),
      ]);
      expect(controller.contentExtent, 24 + 2 * 40);
    });

    testWidgets('the section loading to loaded swaps skeletons for leaves', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 4,
        ),
      ]);
      await pumpViewport(tester);

      snapshots.replaceSections([
        CatalogSection(id: 'a', title: 'A', leaves: [_doc(0), _doc(1)]),
      ]);
      await tester.pump();

      expect(
        paintOnce(tester).circles.where((c) => c.color.toARGB32() == _skeleton),
        isEmpty,
      );
      expect(producer.attempts, hasLength(2));
      expect(controller.contentExtent, 24 + 40);
    });
  });

  group('the empty message row', () {
    testWidgets('a loaded section with no leaves paints it under the header', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          emptyMessage: 'Nothing here yet',
        ),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      // The title and the message.
      expect(canvas.paragraphs, 2);
      expect(canvas.circles, isEmpty);
    });

    testWidgets('it takes one row of the extent', (tester) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          emptyMessage: 'Nothing here yet',
        ),
      ]);
      await pumpViewport(tester);

      expect(controller.contentExtent, 24 + 40);
    });

    testWidgets('without a message the header is alone', (tester) async {
      snapshots.replaceSections([
        const CatalogSection(id: 'a', title: 'A', leaves: []),
      ]);
      await pumpViewport(tester);

      expect(paintOnce(tester).paragraphs, 1);
      expect(controller.contentExtent, 24);
    });

    testWidgets('a section with leaves never shows it', (tester) async {
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [_doc(0)],
          emptyMessage: 'Nothing here yet',
        ),
      ]);
      await pumpViewport(tester);

      expect(paintOnce(tester).paragraphs, 1);
      expect(controller.contentExtent, 24 + 40);
    });

    testWidgets('a section that is still loading shows skeletons instead', (
      tester,
    ) async {
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.loading,
          emptyMessage: 'Nothing here yet',
        ),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.paragraphs, 1);
      expect(canvas.circles, hasLength(_span));
    });

    testWidgets('a tap on it is no leaf hit', (tester) async {
      final hits = <CatalogLeafHit>[];
      snapshots.replaceSections([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          emptyMessage: 'Nothing here yet',
        ),
      ]);
      await pumpViewport(tester, onLeafTap: hits.add);

      final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));
      await tester.tapAt(origin + const Offset(160, 44));
      await tester.pump();

      expect(hits, isEmpty);
    });
  });

  group('a far section jump over every kind of section', () {
    testWidgets('stitches skeletons, message rows and actions without a '
        'hitch', (tester) async {
      CatalogSection loaded(String id) => CatalogSection(
        id: id,
        title: id,
        leaves: [for (var i = 0; i < 40; i++) _doc(i)],
      );
      snapshots.replaceSections([
        const CatalogSection(
          id: 'loading',
          title: 'Loading',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 6,
          action: CatalogSectionAction(id: 'x', label: 'X'),
        ),
        const CatalogSection(
          id: 'empty',
          title: 'Empty',
          leaves: [],
          emptyMessage: 'Nothing yet',
        ),
        for (var i = 0; i < 20; i++) loaded('s$i'),
        const CatalogSection(
          id: 'tail',
          title: 'Tail',
          leaves: [],
          state: CatalogSectionState.failed,
          skeletonCount: 5,
        ),
      ]);
      await pumpViewport(tester);
      final render = tester.renderObject<RenderPanelCatalog>(
        find.byType(PanelCatalogViewport),
      );

      final jump = controller.jumpToSection(22);
      await tester.pump();
      expect(render.isFarStitchActive, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-flight: the outgoing strip holds the skeleton and message rows.
      expect(paintOnce(tester).circles, isNotEmpty);
      await tester.pumpAndSettle();
      await jump;

      expect(render.isFarStitchActive, isFalse);
      expect(
        paintOnce(tester).circles.where((c) => c.color.toARGB32() == _skeleton),
        hasLength(5),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
