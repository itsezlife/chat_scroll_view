import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_section_navigation.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';

Widget _harness({
  required CatalogDataSource dataSource,
  required CatalogAssetCache assetCache,
  required PanelCatalogController controller,
  double width = 320,
  double height = 480,
  int spanCount = 4,
  double cellExtent = 40,
  double headerExtent = 24,
  EdgeInsets padding = EdgeInsets.zero,
  ValueChanged<CatalogLeaf>? onLeafTap,
  void Function(CatalogLeaf leaf, LongPressStartDetails details)?
  onLeafLongPressStart,
  void Function(CatalogLeaf leaf, LongPressMoveUpdateDetails details)?
  onLeafLongPressMove,
  void Function(CatalogLeaf leaf, LongPressEndDetails details)?
  onLeafLongPressEnd,
  bool Function(CatalogLeaf leaf)? leafLongPressEligible,
}) {
  return MaterialApp(
    home: PanelCatalogTheme(
      data: PanelCatalogThemeData.light,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: PanelCatalogViewport(
              dataSource: dataSource,
              assetCache: assetCache,
              controller: controller,
              spanCount: spanCount,
              cellExtent: cellExtent,
              headerExtent: headerExtent,
              padding: padding,
              onLeafTap: onLeafTap,
              onLeafLongPressStart: onLeafLongPressStart,
              onLeafLongPressMove: onLeafLongPressMove,
              onLeafLongPressEnd: onLeafLongPressEnd,
              leafLongPressEligible: leafLongPressEligible,
            ),
          ),
        ),
      ),
    ),
  );
}

CatalogSection _section(String id, List<CatalogLeaf> leaves) =>
    CatalogSection(id: id, title: 'Section $id', leaves: leaves);

List<CatalogSection> _sections(int count, {int leavesPerSection = 8}) => [
  for (var i = 0; i < count; i++)
    _section('s$i', [
      for (var j = 0; j < leavesPerSection; j++)
        CatalogLeaf.unicode(String.fromCharCode(0x1F600 + j)),
    ]),
];

RenderPanelCatalog _render(WidgetTester tester) =>
    tester.renderObject(find.byType(PanelCatalogViewport));

void main() {
  late FakeCatalogDataSource dataSource;
  late FakeCatalogAssetCache assetCache;
  late PanelCatalogController controller;

  setUp(() {
    dataSource = FakeCatalogDataSource();
    assetCache = FakeCatalogAssetCache();
    controller = PanelCatalogController();
  });

  tearDown(() {
    dataSource.dispose();
    controller.dispose();
  });

  testWidgets(
    'catalog body scrolls with absolute content offset against known extent',
    (tester) async {
      final leaves = [
        for (var i = 0; i < 80; i++)
          CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
      ];
      dataSource.replaceSections([_section('a', leaves)]);

      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      final render = _render(tester);
      expect(render.contentExtent, 824);
      expect(render.maxOffset, 824 - 480);
      expect(controller.offset, 0);

      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
      expect(controller.offset, lessThanOrEqualTo(render.maxOffset));
    },
  );

  testWidgets('notifyDataChanged refreshes the projected catalog', (
    tester,
  ) async {
    dataSource.replaceSections([
      _section('a', [const CatalogLeaf.unicode('😀')]),
    ]);

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(_render(tester).projectedAssetKeys, [CatalogAssetKey.unicode('😀')]);

    dataSource.replaceSections([
      _section('b', [
        const CatalogLeaf.unicode('🎉'),
        const CatalogLeaf.unicode('🚀'),
      ]),
    ]);
    await tester.pump();

    final render = _render(tester);
    expect(render.projectedAssetKeys, [
      CatalogAssetKey.unicode('🎉'),
      CatalogAssetKey.unicode('🚀'),
    ]);
    expect(render.contentExtent, 64);
  });

  testWidgets('unready unicode leaves present circle placeholder', (
    tester,
  ) async {
    const leaf = CatalogLeaf.unicode('😀');
    dataSource.replaceSections([
      _section('a', [leaf]),
    ]);

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _render(tester).presentationOf(leaf.assetKey),
      CatalogLeafPresentation.circlePlaceholder,
    );
    expect(kCirclePlaceholderRadiusFactor, 0.4);

    assetCache.markReady(
      CatalogAssetKey.unicode('😀'),
      CatalogAssetCacheType.keyboard,
    );
    await tester.pump();

    expect(
      _render(tester).presentationOf(leaf.assetKey),
      CatalogLeafPresentation.content,
    );
  });

  testWidgets(
    'document-backed leaf identity hooks exist with thumb-first placeholder',
    (tester) async {
      const leaf = CatalogLeaf.document('doc-42');
      dataSource.replaceSections([
        _section('a', [leaf]),
      ]);

      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      final render = _render(tester);
      expect(render.projectedAssetKeys, [CatalogAssetKey.document('doc-42')]);
      expect(
        render.presentationOf(leaf.assetKey),
        CatalogLeafPresentation.thumbFirstPlaceholder,
      );
    },
  );

  testWidgets(
    'cells are paint leaves — element count stays flat as leaf count grows',
    (tester) async {
      Future<int> elementCountFor(int leafCount) async {
        dataSource.replaceSections([
          _section('a', [
            for (var i = 0; i < leafCount; i++)
              CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
          ]),
        ]);
        await tester.pumpWidget(
          _harness(
            dataSource: dataSource,
            assetCache: assetCache,
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();

        final root = tester.element(find.byType(PanelCatalogViewport));
        var count = 0;
        void walk(Element e) {
          count += 1;
          e.visitChildren(walk);
        }

        walk(root);
        return count;
      }

      final small = await elementCountFor(8);
      final large = await elementCountFor(64);

      expect(large, small);
    },
  );

  testWidgets(
    'asset bindings recycle to the visible band as the catalog scrolls',
    (tester) async {
      dataSource.replaceSections([
        _section('a', [
          for (var i = 0; i < 80; i++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
        ]),
      ]);

      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      final atTop = _render(tester).attachedLeafCount;
      expect(atTop, lessThan(80));
      expect(atTop, greaterThan(0));

      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      final afterScroll = _render(tester).attachedLeafCount;
      expect(afterScroll, lessThan(80));
      expect(afterScroll, greaterThan(0));
    },
  );

  testWidgets('tap on a leaf fires onLeafTap with that leaf identity', (
    tester,
  ) async {
    const first = CatalogLeaf.unicode('😀');
    const second = CatalogLeaf.unicode('🎉');
    dataSource.replaceSections([
      _section('a', [first, second]),
    ]);

    CatalogLeaf? tapped;
    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        onLeafTap: (leaf) => tapped = leaf,
      ),
    );
    await tester.pumpAndSettle();

    // Header is 24px; first leaf cell is span col 0 under the header.
    final box = tester.getRect(find.byType(PanelCatalogViewport));
    await tester.tapAt(Offset(box.left + 20, box.top + 24 + 20));
    await tester.pumpAndSettle();

    expect(tapped?.assetKey, first.assetKey);
  });

  testWidgets('tap on a section header does not fire onLeafTap', (
    tester,
  ) async {
    dataSource.replaceSections([
      _section('a', [const CatalogLeaf.unicode('😀')]),
    ]);

    var taps = 0;
    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        onLeafTap: (_) => taps += 1,
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(PanelCatalogViewport));
    await tester.tapAt(Offset(box.left + 20, box.top + 12));
    await tester.pumpAndSettle();

    expect(taps, 0);
  });

  testWidgets(
    'long-press on a leaf fires start/move/end with that leaf identity',
    (tester) async {
      const leaf = CatalogLeaf.unicode('😀');
      dataSource.replaceSections([
        _section('a', [leaf]),
      ]);

      CatalogLeaf? started;
      CatalogLeaf? moved;
      CatalogLeaf? ended;
      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          assetCache: assetCache,
          controller: controller,
          onLeafLongPressStart: (l, _) => started = l,
          onLeafLongPressMove: (l, _) => moved = l,
          onLeafLongPressEnd: (l, _) => ended = l,
        ),
      );
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(PanelCatalogViewport));
      final center = Offset(box.left + 20, box.top + 24 + 20);
      final gesture = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(started?.assetKey, leaf.assetKey);

      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      expect(moved?.assetKey, leaf.assetKey);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(ended?.assetKey, leaf.assetKey);
    },
  );

  testWidgets('leafLongPressEligible skips long-press on ineligible leaves', (
    tester,
  ) async {
    const eligible = CatalogLeaf.unicode('👍');
    const ineligible = CatalogLeaf.unicode('❤️');
    dataSource.replaceSections([
      _section('a', [ineligible, eligible]),
    ]);

    CatalogLeaf? started;
    var taps = 0;
    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        leafLongPressEligible: (leaf) => leaf.assetKey == eligible.assetKey,
        onLeafTap: (_) => taps += 1,
        onLeafLongPressStart: (l, _) => started = l,
        onLeafLongPressMove: (_, _) {},
        onLeafLongPressEnd: (_, _) {},
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(PanelCatalogViewport));
    final ineligibleCenter = Offset(box.left + 20, box.top + 24 + 20);
    final gesture = await tester.startGesture(ineligibleCenter);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(started, isNull);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);

      final eligibleCenter = Offset(box.left + 100, box.top + 24 + 20);
    final eligibleGesture = await tester.startGesture(eligibleCenter);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(started?.assetKey, eligible.assetKey);
    await eligibleGesture.up();
  });

  testWidgets('press scale stays live when long-press wins over tap', (
    tester,
  ) async {
    const leaf = CatalogLeaf.unicode('😀');
    dataSource.replaceSections([
      _section('a', [leaf]),
    ]);

    CatalogLeaf? started;
    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        onLeafTap: (_) {},
        onLeafLongPressStart: (l, _) => started = l,
        onLeafLongPressMove: (_, _) {},
        onLeafLongPressEnd: (_, _) {},
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(PanelCatalogViewport));
    final center = Offset(box.left + 20, box.top + 24 + 20);
    final gesture = await tester.startGesture(center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

    final render = _render(tester);
    expect(started?.assetKey, leaf.assetKey);
    expect(render.pressedLeaf?.assetKey, leaf.assetKey);
    expect(render.pressProgress, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(render.pressProgress, 0);
  });

  testWidgets('pointer down on a leaf starts press scale feedback', (
    tester,
  ) async {
    const leaf = CatalogLeaf.unicode('😀');
    dataSource.replaceSections([
      _section('a', [leaf]),
    ]);

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        onLeafTap: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(PanelCatalogViewport));
    final center = Offset(box.left + 20, box.top + 24 + 20);
    final gesture = await tester.startGesture(center);
    await tester.pump();

    final render = _render(tester);
    expect(render.pressedLeaf?.assetKey, leaf.assetKey);
    expect(render.pressProgress, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(render.pressProgress, 0);
    expect(render.pressedLeaf, isNull);
  });

  testWidgets('drag-end with velocity starts a ballistic fling', (
    tester,
  ) async {
    dataSource.replaceSections([
      _section('a', [
        for (var i = 0; i < 80; i++)
          CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
      ]),
    ]);

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PanelCatalogViewport),
      const Offset(0, -300),
      1000,
    );
    await tester.pump();
    expect(_render(tester).isFlinging, isTrue);
    expect(controller.offset, greaterThan(0));

    await tester.pumpAndSettle();
    expect(_render(tester).isFlinging, isFalse);
  });

  testWidgets('tap during fling stops scroll and does not fire onLeafTap', (
    tester,
  ) async {
    dataSource.replaceSections([
      _section('a', [
        for (var i = 0; i < 80; i++)
          CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
      ]),
    ]);

    var taps = 0;
    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        onLeafTap: (_) => taps += 1,
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PanelCatalogViewport),
      const Offset(0, -400),
      2000,
    );
    await tester.pump();
    expect(_render(tester).isFlinging, isTrue);
    final offsetWhileFlinging = controller.offset;

    final box = tester.getRect(find.byType(PanelCatalogViewport));
    await tester.tapAt(Offset(box.left + 20, box.top + 24 + 20));
    await tester.pump();

    expect(_render(tester).isFlinging, isFalse);
    expect(taps, 0);
    // Coast stopped — offset may still equal the cancel-frame value.
    expect(controller.offset, offsetWhileFlinging);

    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('near-path jumpToSection smooth-scrolls to strip inset landing', (
    tester,
  ) async {
    const stripInset = 36.0;
    final sections = _sections(12, leavesPerSection: 8);
    dataSource.replaceSections(sections);

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        height: 240,
        padding: const EdgeInsets.only(top: stripInset),
      ),
    );
    await tester.pumpAndSettle();

    const targetSection = 1;
    final expectedOffset = scrollOffsetForSectionHeader(
      sectionIndex: targetSection,
      sections: sections,
      spanCount: 4,
      cellExtent: 40,
      headerExtent: 24,
      padding: const EdgeInsets.only(top: stripInset),
    );

    final future = controller.jumpToSection(targetSection);
    await tester.pump();
    expect(controller.isSectionJumpActive, isTrue);
    expect(_render(tester).isSectionJumpAnimating, isTrue);
    expect(_render(tester).isFarStitchActive, isFalse);
    expect(controller.offset, isNot(expectedOffset));

    await tester.pumpAndSettle();
    await future;

    expect(controller.offset, expectedOffset);
    expect(controller.isSectionJumpActive, isFalse);
    expect(_render(tester).isSectionJumpAnimating, isFalse);
  });

  testWidgets('jumpToSection within span×9 gate uses near path not bare jump', (
    tester,
  ) async {
    dataSource.replaceSections(_sections(12, leavesPerSection: 8));

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        height: 240,
        spanCount: 4,
      ),
    );
    await tester.pumpAndSettle();

    final future = controller.jumpToSection(2);
    await tester.pump();
    expect(_render(tester).isSectionJumpAnimating, isTrue);
    expect(_render(tester).isFarStitchActive, isFalse);

    await tester.pumpAndSettle();
    await future;
    expect(_render(tester).isSectionJumpAnimating, isFalse);
    expect(_render(tester).isFarStitchActive, isFalse);
  });

  testWidgets('user drag cancels in-flight section jump', (tester) async {
    dataSource.replaceSections(_sections(12, leavesPerSection: 8));

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        height: 240,
      ),
    );
    await tester.pumpAndSettle();

    final future = controller.jumpToSection(3);
    await tester.pump();
    expect(controller.isSectionJumpActive, isTrue);

    await tester.drag(find.byType(PanelCatalogViewport), const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(controller.isSectionJumpActive, isFalse);
    expect(_render(tester).isSectionJumpAnimating, isFalse);
    await future;
  });

  testWidgets('out-of-range jumpToSection is a silent no-op', (tester) async {
    dataSource.replaceSections(_sections(2));

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    final before = controller.offset;
    await controller.jumpToSection(99);
    await tester.pumpAndSettle();
    expect(controller.offset, before);
  });

  testWidgets('far-path jumpToSection stitches instead of bare jump', (
    tester,
  ) async {
    dataSource.replaceSections(_sections(20, leavesPerSection: 16));

    const viewportHeight = 240.0;
    const spanCount = 4;
    const cellExtent = 40.0;
    const headerExtent = 24.0;
    const padding = EdgeInsets.zero;

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        height: viewportHeight,
        spanCount: spanCount,
        cellExtent: cellExtent,
        headerExtent: headerExtent,
        padding: padding,
      ),
    );
    await tester.pumpAndSettle();

    const targetSection = 19;
    final projection = projectCatalogSlots(
      sections: dataSource.sections,
      spanCount: spanCount,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      padding: padding,
      maxWidth: 320,
    );
    final expectedOffset = scrollOffsetForSectionHeader(
      sectionIndex: targetSection,
      sections: dataSource.sections,
      spanCount: spanCount,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      padding: padding,
    ).clamp(0.0, projection.contentExtent - viewportHeight);

    expect(
      isNearPathSectionJump(
        targetSectionIndex: targetSection,
        sections: dataSource.sections,
        spanCount: spanCount,
        cellExtent: cellExtent,
        headerExtent: headerExtent,
        padding: padding,
        scrollOffset: controller.offset,
        viewportHeight: viewportHeight,
      ),
      isFalse,
      reason: 'fixture must select far path behind span×9 gate',
    );

    final future = controller.jumpToSection(targetSection);
    await tester.pump();

    expect(controller.isSectionJumpActive, isTrue);
    expect(_render(tester).isFarStitchActive, isTrue);
    expect(_render(tester).isSectionJumpAnimating, isFalse);
    expect(controller.offset, expectedOffset);

    await tester.pump(const Duration(milliseconds: 50));
    expect(_render(tester).farStitchProgress, greaterThan(0));
    expect(_render(tester).farStitchProgress, lessThan(1));

    await _driveSectionJump(tester, future);

    expect(controller.offset, expectedOffset);
    expect(controller.isSectionJumpActive, isFalse);
    expect(_render(tester).isFarStitchActive, isFalse);
  });

  testWidgets('user drag cancels in-flight far-path stitch', (tester) async {
    dataSource.replaceSections(_sections(20, leavesPerSection: 16));

    await tester.pumpWidget(
      _harness(
        dataSource: dataSource,
        assetCache: assetCache,
        controller: controller,
        height: 240,
        spanCount: 4,
      ),
    );
    await tester.pumpAndSettle();

    final future = controller.jumpToSection(19);
    await tester.pump();
    expect(_render(tester).isFarStitchActive, isTrue);

    await tester.drag(find.byType(PanelCatalogViewport), const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(controller.isSectionJumpActive, isFalse);
    expect(_render(tester).isFarStitchActive, isFalse);
    await future;
  });
}

Future<void> _driveSectionJump(
  WidgetTester tester,
  Future<void> future, {
  int maxPumps = 200,
}) async {
  await tester.pump();
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await future;
}
