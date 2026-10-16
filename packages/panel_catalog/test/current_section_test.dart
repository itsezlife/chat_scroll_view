/// The current-section event: which section the viewport is in, so a page's
/// strip can show the active category.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource]
/// and a text-glyph scope, observed only through the controller's public
/// `events` and `currentSection`, and the commands that move the catalogue.
///
/// Geometry: six sections `a`..`f` of 20 leaves each, 4 columns of 40 px cells
/// under a 24 px header, so each is 224 tall (headers at 0, 224, ... 1120) in
/// a 320 x 480 viewport; the content is 1344 tall and scrolls to 864.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(String id, {int leaves = 20}) => CatalogSection(
  id: id,
  title: id,
  state: CatalogSectionState.loaded,
  leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode(_glyph(i))],
);

List<CatalogSection> _sections({int lastLeaves = 20}) => [
  for (final id in _ids) _section(id, leaves: id == 'f' ? lastLeaves : 20),
];

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<PanelCatalogScrollEvent> events;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    events = [];
    controller.events.addListener(events.add);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(WidgetTester tester, {double? landingInset}) =>
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
                    spanCount: 4,
                    cellExtent: 40,
                    headerExtent: 24,
                    headerLandingInset: landingInset,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// The ids of the current-section events heard since the last [take].
  List<String> take() {
    final heard = [
      for (final event in events)
        if (event is PanelCatalogCurrentSectionChanged) event.sectionId,
    ];
    events.clear();
    return heard;
  }

  group('a catalogue that mounts', () {
    testWidgets('is in its first section', (tester) async {
      snapshots.replaceSections(_sections());

      await pumpViewport(tester);
      await tester.pump();

      expect(take(), ['a']);
      expect(controller.currentSection?.sectionId, 'a');
      expect(controller.currentSection?.sectionIndex, 0);
    });

    testWidgets('has no current section when it is empty', (tester) async {
      await pumpViewport(tester);
      await tester.pump();

      expect(take(), isEmpty);
      expect(controller.currentSection, isNull);
    });

    testWidgets('says nothing again while nothing moves', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();
      take();

      await tester.pump(const Duration(seconds: 1));

      expect(take(), isEmpty);
    });
  });

  group('scrolling', () {
    testWidgets('changes at the header that reaches the top, once', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();
      take();

      final heard = <String>[];
      for (var offset = 50.0; offset <= 700; offset += 50) {
        controller.jumpTo(offset);
        await tester.pump();
        heard.addAll(take());
      }

      // b's header is at 224 and c's at 448, d's at 672.
      expect(heard, ['b', 'c', 'd']);
    });

    testWidgets('is in the section whose header is above the top, not the '
        'one below it', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();
      take();

      controller.jumpTo(223);
      await tester.pump();
      expect(controller.currentSection?.sectionId, 'a');

      controller.jumpTo(224);
      await tester.pump();
      expect(controller.currentSection?.sectionId, 'b');
    });

    testWidgets('scrolling back changes back', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      controller.jumpTo(500);
      await tester.pump();
      take();

      controller.jumpTo(100);
      await tester.pump();

      expect(take(), ['a']);
    });

    testWidgets('reads the landing inset as the top line', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester, landingInset: 36);
      await tester.pump();
      take();

      // b's header is at 224: it reaches the line at 36 below the top when the
      // offset is 188.
      controller.jumpTo(187);
      await tester.pump();
      expect(controller.currentSection?.sectionId, 'a');

      controller.jumpTo(188);
      await tester.pump();
      expect(controller.currentSection?.sectionId, 'b');
    });

    testWidgets('a drag changes it', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();
      take();

      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(take(), contains('b'));
    });
  });

  group('a section jump', () {
    testWidgets('lands in the section it was sent to', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();

      final jump = controller.jumpToSection(3);
      await tester.pumpAndSettle();
      await jump;

      expect(controller.currentSection?.sectionId, 'd');
    });

    testWidgets('lands in the last section even when it is too short to '
        'bring its header to the top', (tester) async {
      // f is 4 leaves: one row under its header, 48 px, so the content ends
      // before f's header can reach the top.
      snapshots.replaceSections(_sections(lastLeaves: 4));
      await pumpViewport(tester);
      await tester.pump();

      final jump = controller.jumpToSection(5);
      await tester.pumpAndSettle();
      await jump;

      expect(controller.currentSection?.sectionId, 'f');
      expect(controller.currentSection?.sectionIndex, 5);
    });

    testWidgets('a far jump reports the landing, not what it flew over', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();
      take();

      final jump = controller.jumpToSection(5);
      await tester.pumpAndSettle();
      await jump;

      final heard = take();
      expect(heard.last, 'f');
      expect(heard.toSet(), hasLength(heard.length));
    });
  });

  group('a catalogue that changes', () {
    testWidgets('keeps the section when sections come in below it', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('a', leaves: 40),
        _section('b', leaves: 40),
      ]);
      await pumpViewport(tester);
      // The content ends 368 down, with b's header (at 424) in view.
      controller.jumpTo(368);
      await tester.pump();
      expect(controller.currentSection?.sectionId, 'b');
      take();

      snapshots.replaceSections(_sections());
      await tester.pump();

      // Now b's header is at 224 and the line at 368 is still below it.
      expect(take(), isEmpty);
      expect(controller.currentSection?.sectionId, 'b');
    });

    testWidgets('follows a section that moves to another index', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      controller.jumpTo(300);
      await tester.pump();
      expect(controller.currentSection?.sectionId, 'b');
      take();

      // A section appears above: the line at 300 is now inside the second
      // section, which is the one that was first.
      snapshots.replaceSections([_section('z'), ..._sections()]);
      await tester.pump();

      expect(controller.currentSection?.sectionId, 'a');
      expect(controller.currentSection?.sectionIndex, 1);
      expect(take(), ['a']);
    });

    testWidgets('a catalogue that fits has the first section current', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a'), _section('b')]);

      await pumpViewport(tester);
      await tester.pump();

      expect(controller.currentSection?.sectionId, 'a');
    });

    testWidgets('does not move the scroll activity', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      await tester.pump();

      expect(events.whereType<PanelCatalogCurrentSectionChanged>(), isNotEmpty);
      expect(events.whereType<PanelCatalogScrollingChanged>(), isEmpty);
    });
  });
}
