/// The near-viewport events: when the controller tells a page that an edge of a
/// section has come close enough to load it or load more of it.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource]
/// and a text-glyph scope, observed only through the controller's public
/// `events` Observable and the commands that move the catalogue.
///
/// Geometry: six sections `a`..`f` of 20 leaves each, 4 columns of 40 px cells
/// under a 24 px header, so each is 224 tall (tops 0, 224, ... 1120) in a
/// 320 x 480 viewport. With a near extent of 0 the window is the viewport; the
/// default is one viewport height beyond it on each side.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

const _span = 4;
const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(
  String id, {
  int leaves = 20,
  CatalogSectionState state = CatalogSectionState.loaded,
}) => CatalogSection(
  id: id,
  title: id,
  state: state,
  leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode(_glyph(i))],
);

List<CatalogSection> _sections() => [for (final id in _ids) _section(id)];

typedef _Near = (String, CatalogSectionEdge);

const _leading = CatalogSectionEdge.leading;
const _trailing = CatalogSectionEdge.trailing;

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

  Future<void> pumpViewport(WidgetTester tester, {double? nearExtent = 0}) =>
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
                    sectionNearExtent: nearExtent,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// The near events heard since the last [take], in order.
  List<_Near> take() {
    final near = [
      for (final event in events)
        if (event is PanelCatalogSectionNearViewport)
          (event.sectionId, event.edge),
    ];
    events.clear();
    return near;
  }

  group('a catalogue that mounts', () {
    testWidgets('announces the edges inside the window, top first', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());

      await pumpViewport(tester);

      // The viewport is [0, 480]: tops 0, 224, 448 and bottoms 224, 448 are in
      // it.
      expect(take(), [
        ('a', _leading),
        ('a', _trailing),
        ('b', _leading),
        ('b', _trailing),
        ('c', _leading),
      ]);
    });

    testWidgets('reaches one viewport further by default', (tester) async {
      snapshots.replaceSections(_sections());

      await pumpViewport(tester, nearExtent: null);

      // The window is [-480, 960]: tops up to 896 and bottoms up to 896.
      expect(take(), [
        ('a', _leading),
        ('a', _trailing),
        ('b', _leading),
        ('b', _trailing),
        ('c', _leading),
        ('c', _trailing),
        ('d', _leading),
        ('d', _trailing),
        ('e', _leading),
      ]);
    });

    testWidgets('says nothing again while nothing moves', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      take();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(take(), isEmpty);
    });

    testWidgets('an empty catalogue announces nothing', (tester) async {
      await pumpViewport(tester);

      expect(take(), isEmpty);
    });
  });

  group('a slow scroll', () {
    testWidgets('announces an edge once, as it comes inside the window', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      take();

      final heard = <_Near>[];
      for (var offset = 20.0; offset <= 240; offset += 20) {
        controller.jumpTo(offset);
        await tester.pump();
        heard.addAll(take());
      }

      // Window [240, 720] at the end: c's bottom (672) and d's top (672) came
      // in, once each, at the step that crossed 672 - 480 = 192.
      expect(heard, [('c', _trailing), ('d', _leading)]);
    });

    testWidgets('scrolling back announces an edge that left again', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      controller.jumpTo(300);
      await tester.pump();
      take();

      // Window [300, 780] has left a's edges (0 and 224) behind.
      controller.jumpTo(0);
      await tester.pump();

      expect(take(), [('a', _leading), ('a', _trailing), ('b', _leading)]);
    });

    testWidgets('a drag announces the edges it uncovers', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      take();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PanelCatalogViewport)),
      );
      await gesture.moveBy(const Offset(0, -100));
      await gesture.moveBy(const Offset(0, -100));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Offset 300 at least: window reaches 780 and c's bottom (672) is in.
      expect(take(), contains(('c', _trailing)));
    });
  });

  group('a fast scroll or a jump', () {
    testWidgets('announces where it lands and not what it flew over', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      take();

      controller.jumpTo(860);
      await tester.pump();

      // Window [860, 1340]: d's bottom 896, e's top 896 and bottom 1120, f's
      // top 1120 and bottom 1344 (the 1344 content end is past 1340).
      expect(take(), [
        ('d', _trailing),
        ('e', _leading),
        ('e', _trailing),
        ('f', _leading),
      ]);
    });

    testWidgets('a far section jump announces only the landing', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      take();

      final jump = controller.jumpToSection(5);
      await tester.pumpAndSettle();
      await jump;

      final heard = take();
      expect(heard, contains(('f', _leading)));
      expect(heard.map((e) => e.$1), isNot(contains('b')));
      expect(heard.map((e) => e.$1), isNot(contains('c')));
      // Each edge is announced once however long the jump took.
      expect(heard.toSet(), hasLength(heard.length));
    });

    testWidgets('a near section jump announces edges as the window reaches '
        'them', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      take();

      final jump = controller.jumpToSection(1);
      await tester.pumpAndSettle();
      await jump;

      // The landing offset is 224: window [224, 704].
      expect(take(), [('c', _trailing), ('d', _leading)]);
    });
  });

  group('a section that changes', () {
    testWidgets('more leaves while its edge is still near ask again', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', leaves: 4)]);
      await pumpViewport(tester);
      take();

      snapshots.replaceSections([_section('a', leaves: 8)]);
      await tester.pump();

      // The page was told a's end is near, loaded 4 more and the end is still
      // near: it is told again, once. Its start has not moved.
      expect(take(), [('a', _trailing)]);
    });

    testWidgets('only the section whose leaves changed asks again', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', leaves: 4), _section('b')]);
      await pumpViewport(tester);
      take();

      snapshots.replaceSections([_section('a', leaves: 4), _section('b')]);
      await tester.pump();
      expect(take(), isEmpty);

      snapshots.replaceSections([_section('a', leaves: 8), _section('b')]);
      await tester.pump();
      expect(take().map((e) => e.$1).toSet(), {'a'});
    });

    testWidgets('a failure does not ask again by itself', (tester) async {
      snapshots.replaceSections([
        _section('a', leaves: 0, state: CatalogSectionState.loading),
      ]);
      await pumpViewport(tester);
      take();

      snapshots.replaceSections([
        _section('a', leaves: 0, state: CatalogSectionState.failed),
      ]);
      await tester.pump();

      expect(take(), isEmpty);
    });

    testWidgets('a section that comes into being near the viewport is '
        'announced', (tester) async {
      snapshots.replaceSections([_section('a', leaves: 4)]);
      await pumpViewport(tester);
      take();

      snapshots.replaceSections([_section('a', leaves: 4), _section('b')]);
      await tester.pump();

      expect(take(), [('b', _leading), ('b', _trailing)]);
    });
  });

  group('beside the scroll activity', () {
    testWidgets('they are no motion', (tester) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);

      expect(events.whereType<PanelCatalogSectionNearViewport>(), isNotEmpty);
      expect(events.whereType<PanelCatalogScrollingChanged>(), isEmpty);
    });

    testWidgets('they come with the scroll events of the same motion', (
      tester,
    ) async {
      snapshots.replaceSections(_sections());
      await pumpViewport(tester);
      events.clear();

      controller.jumpTo(860);
      await tester.pump();

      expect(events.first, isA<PanelCatalogProgrammaticJump>());
      expect(events.whereType<PanelCatalogSectionNearViewport>(), isNotEmpty);
      // The motion is reported moving once, and the settle follows after the
      // near events, with the same bake pause rules as without them.
      await tester.pumpAndSettle();
      final activity = events
          .where(
            (e) =>
                e is PanelCatalogScrollingChanged ||
                e is PanelCatalogScrollSettled,
          )
          .toList();
      expect(activity.first, isA<PanelCatalogScrollingChanged>());
      expect(
        (activity.first as PanelCatalogScrollingChanged).scrolling,
        isTrue,
      );
      expect(activity.last, isA<PanelCatalogScrollSettled>());
    });
  });

  group('a viewport that leaves the tree and comes back', () {
    testWidgets('announces the near edges again', (tester) async {
      snapshots.replaceSections(_sections());
      final key = GlobalKey();
      final viewport = KeyedSubtree(
        key: key,
        child: PanelCatalogViewport(
          snapshots: snapshots,
          assets: textGlyphScope(),
          controller: controller,
          spanCount: _span,
          cellExtent: 40,
          headerExtent: 24,
          sectionNearExtent: 0,
        ),
      );
      Widget app(Widget child) => MaterialApp(
        home: PanelCatalogTheme(
          data: PanelCatalogThemeData.light,
          child: SizedBox(width: 320, height: 480, child: child),
        ),
      );
      await tester.pumpWidget(app(viewport));
      expect(take(), isNotEmpty);

      // Reparenting under the global key detaches and re-attaches the render
      // object without disposing it.
      await tester.pumpWidget(
        app(Padding(padding: EdgeInsets.zero, child: viewport)),
      );

      expect(take(), [
        ('a', _leading),
        ('a', _trailing),
        ('b', _leading),
        ('b', _trailing),
        ('c', _leading),
      ]);
    });
  });
}
