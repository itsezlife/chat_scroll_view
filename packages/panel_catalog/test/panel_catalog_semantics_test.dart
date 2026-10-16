/// What a screen reader sees of the catalog: semantic nodes for the visible
/// leaves plus a small overscan, never for the whole catalogue.
///
/// **Seam:** [PanelCatalogViewport] with semantics switched on
/// (`tester.ensureSemantics()`), observed through the semantics tree the
/// platform would receive (the children of the viewport's node: label, rect,
/// flags, actions) and the actions performed on it, which must reach the same
/// shell callbacks a pointer does.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';
import 'support/semantics_support.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480 viewport:
// 12 rows of leaves are in view, 48 leaves, and one overscan row (one cell
// extent) on each side.
const _span = 4;
const _viewportHeight = 480.0;
const _inView = 48;

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(
  String id,
  int count, {
  CatalogSectionAction? action,
  TextDirection? direction,
  String? emptyMessage,
}) => CatalogSection(
  id: id,
  title: 'Title $id',
  action: action,
  emptyMessage: emptyMessage,
  layout: direction == null
      ? null
      : SectionLayout.grid(textDirection: direction),
  leaves: [
    for (var i = 0; i < count; i++)
      CatalogLeaf.unicode(_glyph(i % 80), spokenName: 'leaf $id $i'),
  ],
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<CatalogLeafHit> taps;
  late List<CatalogLeafHit> longPresses;
  late List<(String, String)> actions;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    taps = [];
    longPresses = [];
    actions = [];
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    AssetCacheScope? assets,
    bool longPress = true,
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
                height: _viewportHeight,
                child: PanelCatalogViewport(
                  snapshots: snapshots,
                  assets: assets ?? textGlyphScope(),
                  controller: controller,
                  spanCount: _span,
                  cellExtent: 40,
                  headerExtent: 24,
                  onLeafTap: taps.add,
                  onLeafLongPressStart: longPress
                      ? (hit, details) => longPresses.add(hit)
                      : null,
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

  List<SemanticsNode> nodes(WidgetTester tester) => viewportNodes(tester);

  SemanticsNode nodeLabelled(WidgetTester tester, String label) =>
      viewportNodeLabelled(tester, label);

  void perform(WidgetTester tester, SemanticsNode node, SemanticsAction a) =>
      performSemanticsAction(tester, node, a);

  group('a window, not the catalogue', () {
    testWidgets('the node count does not grow with the number of leaves', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 200)]);
      await pumpViewport(tester);
      final small = nodes(tester).length;

      snapshots.replaceSections([
        for (var i = 0; i < 40; i++) _section('s$i', 500),
      ]);
      await tester.pump();
      final large = nodes(tester).length;

      // 20 000 leaves in the second catalogue, 200 in the first.
      expect(large, small);
      expect(large, lessThan(_inView + 4 * _span + 4));
      handle.dispose();
    });

    testWidgets('covers the visible leaves and one overscan row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);

      final labels = nodes(tester).map((n) => n.label).toSet();

      expect(labels, contains('leaf a 0'));
      expect(labels, contains('leaf a ${_inView - 1}'));
      expect(labels, contains('leaf a ${_inView + _span - 1}'));
      expect(labels, isNot(contains('leaf a ${_inView + _span}')));
      handle.dispose();
    });

    testWidgets('slides with the scroll offset', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 4000)]);
      await pumpViewport(tester);
      final before = nodes(tester).length;

      controller.jumpTo(24 + 40 * 500);
      await tester.pump();

      final labels = nodes(tester).map((n) => n.label).toSet();
      expect(labels, contains('leaf a 2000'));
      expect(labels, isNot(contains('leaf a 0')));
      // Mid-catalogue there is overscan above too, and the rows touching the
      // window's edges count.
      expect(nodes(tester).length, lessThanOrEqualTo(before + 3 * _span));
      handle.dispose();
    });

    testWidgets('keeps the node of a leaf that stays in the window', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);
      final id = nodeLabelled(tester, 'leaf a 20').id;

      controller.scrollBy(40);
      await tester.pump();

      expect(nodeLabelled(tester, 'leaf a 20').id, id);
      handle.dispose();
    });

    testWidgets('a node sits where its leaf is painted', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);
      controller.jumpTo(100);
      await tester.pump();

      // Leaf 9: row 2, column 1; row 2 starts 24 + 80 = 104 in content.
      final node = nodeLabelled(tester, 'leaf a 9');

      expect(viewportRectOf(node), const Rect.fromLTWH(80, 4, 80, 40));
      handle.dispose();
    });
  });

  group('nothing to describe', () {
    testWidgets('an empty catalogue has no node and raises nothing', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections(const []);
      await pumpViewport(tester);

      expect(nodes(tester), isEmpty);

      snapshots.replaceSections([_section('a', 4)]);
      await tester.pump();
      expect(nodes(tester), isNotEmpty);
      handle.dispose();
    });

    testWidgets('a band with no area has no node', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'Title a',
          layout: const SectionLayout.grid(headerExtent: 0),
          leaves: [CatalogLeaf.unicode('👍')],
        ),
      ]);
      await pumpViewport(tester);

      expect(nodes(tester).map((n) => n.label), ['👍']);
      handle.dispose();
    });
  });

  group('direction', () {
    testWidgets('a right-to-left grid puts the first leaf at the right', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8)]);
      await pumpViewport(tester, direction: TextDirection.rtl);

      expect(
        viewportRectOf(nodeLabelled(tester, 'leaf a 0')),
        const Rect.fromLTWH(240, 24, 80, 40),
      );
      expect(
        viewportRectOf(nodeLabelled(tester, 'leaf a 3')),
        const Rect.fromLTWH(0, 24, 80, 40),
      );
      handle.dispose();
    });

    testWidgets('reading order is the leaf order in both directions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8)]);

      for (final direction in TextDirection.values) {
        await pumpViewport(tester, direction: direction);
        final ordered = nodes(tester);
        expect(
          [for (final n in ordered.skip(1)) n.label],
          [for (var i = 0; i < 8; i++) 'leaf a $i'],
          reason: '$direction',
        );
      }
      handle.dispose();
    });
  });

  group('a leaf node', () {
    testWidgets('is labelled with the spoken name', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8)]);
      await pumpViewport(tester);

      final data = nodeLabelled(tester, 'leaf a 2').getSemanticsData();

      expect(data.label, 'leaf a 2');
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('without a spoken name a unicode leaf reads as the glyph', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [CatalogLeaf.unicode('👍')],
        ),
      ]);
      await pumpViewport(tester);

      expect(nodes(tester).map((n) => n.label), contains('👍'));
      handle.dispose();
    });

    testWidgets('tap reaches the callback with the hit a pointer gives', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8), _section('b', 8)]);
      await pumpViewport(tester);
      final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));

      perform(tester, nodeLabelled(tester, 'leaf a 5'), SemanticsAction.tap);
      // Leaf 5: row 1, column 1, below a 24 px header.
      await tester.tapAt(origin + const Offset(120, 24 + 40 + 20));

      expect(taps, hasLength(2));
      expect(taps[0], taps[1]);
      expect(taps[0].sectionId, 'a');
      expect(taps[0].index, 5);
      expect(taps[0].leaf, snapshots.value.sections[0].leaves[5]);
      handle.dispose();
    });

    testWidgets('long-press is offered when the shell has one', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8)]);
      await pumpViewport(tester);

      final node = nodeLabelled(tester, 'leaf a 1');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      perform(tester, node, SemanticsAction.longPress);

      expect(longPresses.single.index, 1);
      handle.dispose();
    });

    testWidgets('has no long-press without a shell handler', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8)]);
      await pumpViewport(tester, longPress: false);

      expect(
        nodeLabelled(
          tester,
          'leaf a 1',
        ).getSemanticsData().hasAction(SemanticsAction.longPress),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('follows the long-press eligibility of the shell', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 8)]);
      await tester.pumpWidget(
        MaterialApp(
          home: PanelCatalogTheme(
            data: PanelCatalogThemeData.light,
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
                onLeafLongPressStart: (hit, details) {},
                leafLongPressEligible: (hit) => hit.index.isEven,
              ),
            ),
          ),
        ),
      );

      bool offered(String label) => nodeLabelled(
        tester,
        label,
      ).getSemanticsData().hasAction(SemanticsAction.longPress);

      expect(offered('leaf a 0'), isTrue);
      expect(offered('leaf a 1'), isFalse);
      handle.dispose();
    });
  });

  group('sections', () {
    testWidgets('a header is a labelled header node', (tester) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 4)]);
      await pumpViewport(tester);

      final data = nodeLabelled(tester, 'Title a').getSemanticsData();

      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('the header action is a button that reaches the shell', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([
        _section(
          'a',
          4,
          action: const CatalogSectionAction(
            id: 'more',
            label: 'More',
            semanticLabel: 'Show all of a',
          ),
        ),
      ]);
      await pumpViewport(tester);

      final node = nodeLabelled(tester, 'Show all of a');
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      perform(tester, node, SemanticsAction.tap);

      expect(actions, [('a', 'more')]);
      handle.dispose();
    });

    testWidgets('an action without a semantic label reads as its label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([
        _section(
          'a',
          4,
          action: const CatalogSectionAction(id: 'more', label: 'More'),
        ),
      ]);
      await pumpViewport(tester);

      expect(nodes(tester).map((n) => n.label), contains('More'));
      handle.dispose();
    });

    testWidgets('an empty section reads its message, a skeleton nothing', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([
        _section('a', 0, emptyMessage: 'Nothing here'),
        const CatalogSection(
          id: 'b',
          title: 'Title b',
          leaves: [],
          state: CatalogSectionState.loading,
          skeletonCount: 8,
        ),
      ]);
      await pumpViewport(tester);

      expect(nodes(tester).map((n) => n.label).toList(), [
        'Title a',
        'Nothing here',
        'Title b',
      ]);
      handle.dispose();
    });
  });

  group('scrolling', () {
    testWidgets('the viewport node can be scrolled by a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);
      final root = tester.getSemantics(find.byType(PanelCatalogViewport));

      final data = root.getSemanticsData();
      expect(data.hasAction(SemanticsAction.scrollUp), isTrue);
      expect(data.hasAction(SemanticsAction.scrollDown), isFalse);
      expect(data.scrollExtentMax, controller.maxScrollExtent);

      perform(tester, root, SemanticsAction.scrollUp);
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      expect(
        tester
            .getSemantics(find.byType(PanelCatalogViewport))
            .getSemanticsData()
            .hasAction(SemanticsAction.scrollDown),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('showing a node on screen scrolls its leaf into view', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester);

      // One overscan row below the viewport.
      final node = nodeLabelled(tester, 'leaf a ${_inView + 1}');
      expect(viewportRectOf(node).bottom, greaterThan(_viewportHeight));
      perform(tester, node, SemanticsAction.showOnScreen);
      await tester.pump();

      // Leaf 49 is in row 12, which ends at 24 + 13 * 40 = 544.
      expect(controller.offset, 24 + 40 * 13 - _viewportHeight);
      handle.dispose();
    });
  });

  group('the cost of describing the window', () {
    testWidgets('does not ask the glyph source for a sprite', (tester) async {
      final handle = tester.ensureSemantics();
      final source = _CountingSource();
      final scope = AssetCacheScope(glyphSource: source);
      addTearDown(scope.dispose);
      snapshots.replaceSections([_section('a', 400)]);
      await pumpViewport(tester, assets: scope);
      final paintedOnly = source.spriteCalls;
      expect(paintedOnly, greaterThan(0), reason: 'painting asks, once each');

      // A semantics-only update: a node tree rebuilt, nothing repainted.
      tester
          .renderObject(find.byType(PanelCatalogViewport))
          .markNeedsSemanticsUpdate();
      await tester.pump();

      expect(source.spriteCalls, paintedOnly);
      handle.dispose();
    });
  });
}

class _CountingSource implements GlyphSpriteSource {
  int spriteCalls = 0;

  @override
  AtlasSprite? spriteOf(String glyph) {
    spriteCalls++;
    return null;
  }

  @override
  SpritePageHold? holdPageOf(String glyph) => null;

  @override
  bool waitsForSprite(String glyph) => true;

  @override
  void addPageListener(void Function(int pageIndex) listener) {}

  @override
  void removePageListener(void Function(int pageIndex) listener) {}
}
