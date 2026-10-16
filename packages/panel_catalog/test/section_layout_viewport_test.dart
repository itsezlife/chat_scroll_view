/// A viewport holding sections with different layouts: extents, hits,
/// section jumps (near and far path), stitch continuity and the visible band.
///
/// **Seam:** [PanelCatalogViewport] driven with a [FakeCatalogSnapshotSource]
/// and a `TextGlyphProducer` scope, observed through the controller, the shell
/// callbacks, the controller's settled events and the render object's
/// published geometry.
///
/// Geometry (400 wide, 400 tall; viewport defaults 8 columns, 48 cell, 32
/// header): an 8-column section of 3 rows is 176 tall; a 5-column section with
/// 80 cells and a 40 header of 3 rows is 280 tall.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_far_stitch.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

const _stickers = SectionLayout.grid(
  spanCount: 5,
  cellExtent: 80,
  headerExtent: 40,
);

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CatalogSection _section(
  String id,
  int count, {
  SectionLayout? layout,
  int from = 0,
}) => CatalogSection(
  id: id,
  title: id,
  layout: layout,
  leaves: [
    for (var i = from; i < from + count; i++) CatalogLeaf.unicode(_glyph(i)),
  ],
);

/// 8-column and 5-column sections alternating: 128 + 360 tall per pair.
List<CatalogSection> _alternating(int pairs) => [
  for (var p = 0; p < pairs; p++) ...[
    _section('e$p', 16, from: p * 40),
    _section('s$p', 16, from: p * 40 + 16, layout: _stickers),
  ],
];

Widget _app({
  required FakeCatalogSnapshotSource snapshots,
  required AssetCacheScope assets,
  required PanelCatalogController controller,
  ValueChanged<CatalogLeafHit>? onLeafTap,
  void Function(CatalogLeafHit, LongPressStartDetails)? onLongPressStart,
}) => MaterialApp(
  home: PanelCatalogTheme(
    data: PanelCatalogThemeData.light,
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: PanelCatalogViewport(
            snapshots: snapshots,
            assets: assets,
            controller: controller,
            spanCount: 8,
            cellExtent: 48,
            headerExtent: 32,
            onLeafTap: onLeafTap,
            onLeafLongPressStart: onLongPressStart,
            onLeafLongPressMove: onLongPressStart == null ? null : (_, _) {},
            onLeafLongPressEnd: onLongPressStart == null ? null : (_, _) {},
          ),
        ),
      ),
    ),
  ),
);

RenderPanelCatalog _render(WidgetTester tester) =>
    tester.renderObject(find.byType(PanelCatalogViewport));

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late AssetCacheScope assetScope;
  late PanelCatalogController controller;
  late List<PanelCatalogScrollEvent> events;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    assetScope = textGlyphScope();
    controller = PanelCatalogController();
    events = [];
    controller.events.listen(events.add);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    ValueChanged<CatalogLeafHit>? onLeafTap,
    void Function(CatalogLeafHit, LongPressStartDetails)? onLongPressStart,
  }) async {
    await tester.pumpWidget(
      _app(
        snapshots: snapshots,
        assets: assetScope,
        controller: controller,
        onLeafTap: onLeafTap,
        onLongPressStart: onLongPressStart,
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset viewportPoint(WidgetTester tester, double x, double y) =>
      tester.getTopLeft(find.byType(PanelCatalogViewport)) + Offset(x, y);

  group('layout extents', () {
    testWidgets('the content extent adds up each section by its own layout', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('emoji', 24),
        _section('stickers', 12, layout: _stickers),
        _section('more', 16),
      ]);

      await pump(tester);

      // 8-col: 32 + 3 * 48; 5-col: 40 + 3 * 80; 8-col: 32 + 2 * 48.
      expect(_render(tester).contentExtent, 176 + 280 + 128);
      expect(_render(tester).maxOffset, 176 + 280 + 128 - 400);
    });

    testWidgets('a new snapshot that changes a layout relays out', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 24)]);
      await pump(tester);
      expect(_render(tester).contentExtent, 176);

      snapshots.replaceSections([_section('a', 24, layout: _stickers)]);
      await tester.pump();

      expect(_render(tester).contentExtent, 40 + 5 * 80);
    });
  });

  group('taps and long presses', () {
    testWidgets('a tap in each section names that section\'s own cell', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('emoji', 24),
        _section('stickers', 12, layout: _stickers, from: 100),
      ]);
      final taps = <CatalogLeafHit>[];
      await pump(tester, onLeafTap: taps.add);

      // 8 columns of 50: index 9 is row 1, column 1 under the 32 header.
      await tester.tapAt(viewportPoint(tester, 75, 32 + 48 + 24));
      // 5 columns of 80 under the section at 176 with a 40 header: index 7 is
      // row 1, column 2. The same x would be column 4 of an 8-column grid.
      await tester.tapAt(viewportPoint(tester, 200, 176 + 40 + 80 + 40));
      await tester.pumpAndSettle();

      expect(taps, [
        CatalogLeafHit(
          sectionId: 'emoji',
          index: 9,
          leaf: CatalogLeaf.unicode(_glyph(9)),
        ),
        CatalogLeafHit(
          sectionId: 'stickers',
          index: 7,
          leaf: CatalogLeaf.unicode(_glyph(107)),
        ),
      ]);
      expect(taps.last.leaf, CatalogLeaf.unicode(_glyph(107)));
    });

    testWidgets('a long press reports the cell of the section it is in', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('emoji', 24),
        _section('stickers', 12, layout: _stickers, from: 100),
      ]);
      final started = <CatalogLeafHit>[];
      await pump(
        tester,
        onLeafTap: (_) {},
        onLongPressStart: (hit, _) => started.add(hit),
      );

      await tester.longPressAt(viewportPoint(tester, 330, 176 + 40 + 40));
      await tester.pumpAndSettle();

      // Column 4 of the 5-column grid, first row.
      expect(started.single.sectionId, 'stickers');
      expect(started.single.index, 4);
    });

    testWidgets('the same key in two sections is two distinct hits', (
      tester,
    ) async {
      final shared = CatalogLeaf.unicode('😀', tag: 'from-recents');
      snapshots.replaceSections([
        CatalogSection(id: 'recents', title: 'r', leaves: [shared]),
        CatalogSection(
          id: 'all',
          title: 'a',
          layout: _stickers,
          leaves: [CatalogLeaf.unicode('😀', tag: 'from-all')],
        ),
      ]);
      final taps = <CatalogLeafHit>[];
      await pump(tester, onLeafTap: taps.add);

      await tester.tapAt(viewportPoint(tester, 25, 32 + 24));
      await tester.tapAt(viewportPoint(tester, 40, 32 + 48 + 40 + 40));
      await tester.pumpAndSettle();

      expect(taps, hasLength(2));
      expect(taps[0].leaf, taps[1].leaf, reason: 'one content, equal leaves');
      expect(taps[0], isNot(taps[1]), reason: 'two cells, two hits');
      expect([taps[0].sectionId, taps[1].sectionId], ['recents', 'all']);
      expect(
        [taps[0].leaf.tag, taps[1].leaf.tag],
        ['from-recents', 'from-all'],
      );
    });

    testWidgets(
      'a header, an inset and the padding below the cells hit nothing',
      (tester) async {
        snapshots.replaceSections([
          _section(
            'a',
            3,
            layout: const SectionLayout.grid(
              insets: EdgeInsets.fromLTRB(40, 0, 0, 0),
            ),
          ),
        ]);
        final taps = <CatalogLeafHit>[];
        await pump(tester, onLeafTap: taps.add);

        await tester.tapAt(viewportPoint(tester, 100, 10)); // header
        await tester.tapAt(viewportPoint(tester, 20, 32 + 20)); // inset
        await tester.tapAt(viewportPoint(tester, 100, 300)); // below the rows
        await tester.pumpAndSettle();
        expect(taps, isEmpty);

        // Column 0 starts after the 40 inset: 360 / 8 = 45 wide cells.
        await tester.tapAt(viewportPoint(tester, 40 + 20, 32 + 20));
        await tester.pumpAndSettle();
        expect(taps.single.index, 0);
      },
    );
  });

  group('section jumps across layouts', () {
    testWidgets('lands a 5-column section by the extents above it', (
      tester,
    ) async {
      snapshots.replaceSections(_alternating(6));
      await pump(tester);

      final future = controller.jumpToSection(1);
      await tester.pump();
      expect(_render(tester).isSectionJumpAnimating, isTrue);
      expect(_render(tester).isFarStitchActive, isFalse);
      await tester.pumpAndSettle();
      await future;

      // The 8-column section above is 128 tall.
      expect(controller.offset, 128);
    });

    testWidgets('a far target takes the stitch and lands exactly', (
      tester,
    ) async {
      snapshots.replaceSections(_alternating(6));
      await pump(tester);

      // 5 pairs of (128 + 360) above section 10, a literal not read from the
      // code under test; the content is 6 * 488, so it fits without a clamp.
      final future = controller.jumpToSection(10);
      await tester.pump();
      expect(_render(tester).isFarStitchActive, isTrue);
      expect(_render(tester).isSectionJumpAnimating, isFalse);
      await tester.pumpAndSettle();
      await future;

      expect(controller.offset, 5 * 488);
      expect(_render(tester).isFarStitchActive, isFalse);
    });

    testWidgets('a target within the nine-row gate is near whatever its span', (
      tester,
    ) async {
      snapshots.replaceSections(_alternating(6));
      await pump(tester);
      controller.jumpTo(2000);
      await tester.pump();

      // Section 8 starts at 1952 (4 pairs): its header is above the viewport,
      // one flat row from the first visible row.
      final future = controller.jumpToSection(8);
      await tester.pump();
      expect(_render(tester).isSectionJumpAnimating, isTrue);
      await tester.pumpAndSettle();
      await future;

      expect(controller.offset, 4 * 488);
    });

    testWidgets('an in-flight stitch between layouts settles on the target', (
      tester,
    ) async {
      snapshots.replaceSections(_alternating(6));
      await pump(tester);
      controller.jumpTo(2000);
      await tester.pump();
      expect(_render(tester).contentExtent, 6 * 488);

      final future = controller.jumpToSection(0);
      await tester.pump();
      expect(_render(tester).isFarStitchActive, isTrue);
      var progress = 0.0;
      for (var i = 0; i < 30 && _render(tester).isFarStitchActive; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          _render(tester).farStitchProgress,
          greaterThanOrEqualTo(progress),
        );
        progress = _render(tester).farStitchProgress;
      }
      await tester.pumpAndSettle();
      await future;

      expect(controller.offset, 0);
      expect(_render(tester).isFarStitchActive, isFalse);
    });
  });

  group('stitch capture across layouts', () {
    List<CatalogLayoutSlot> project(List<CatalogSection> sections) =>
        CatalogSlotProjection.project(
          sections: sections,
          spanCount: 8,
          cellExtent: 48,
          headerExtent: 32,
          padding: EdgeInsets.zero,
          maxWidth: 400,
        ).slots;

    test('the outgoing strip keeps each section\'s own cells', () {
      final slots = project(_alternating(2));

      // The viewport [100, 300) crosses e0 (0..128) and s0 (128..488).
      final outgoing = CatalogFarStitch.captureOutgoing(
        slots: slots,
        scrollOffset: 100,
        viewportHeight: 200,
      );

      final leaves = outgoing.whereType<CatalogStitchCapturedLeaf>().toList();
      final fromEmoji = leaves.where((l) => l.sectionId == 'e0');
      final fromStickers = leaves.where((l) => l.sectionId == 's0');
      expect(fromEmoji, isNotEmpty);
      expect(fromStickers, isNotEmpty);
      expect(fromEmoji.every((l) => l.width == 50 && l.height == 48), isTrue);
      expect(
        fromStickers.every((l) => l.width == 80 && l.height == 80),
        isTrue,
      );
      final headers = outgoing.whereType<CatalogStitchCapturedHeader>();
      expect(headers.map((h) => h.height), [40]);
      expect(headers.single.width, 400);
    });

    test('the same key in another cell is incoming, not outgoing', () {
      final shared = CatalogLeaf.unicode('😀');
      final slots = project([
        CatalogSection(id: 'a', title: 'a', leaves: [shared]),
        CatalogSection(
          id: 'b',
          title: 'b',
          layout: _stickers,
          leaves: [shared],
        ),
      ]);
      // Only section a is on screen before the jump.
      final outgoing = CatalogFarStitch.captureOutgoing(
        slots: slots,
        scrollOffset: 0,
        viewportHeight: 60,
      );
      final cells = slots.whereType<CatalogLeafSlot>().toList();

      expect(CatalogFarStitch.slotIsOutgoing(cells[0], outgoing), isTrue);
      expect(CatalogFarStitch.slotIsOutgoing(cells[1], outgoing), isFalse);
    });

    test('the travel spans the incoming strip of the target layout', () {
      final slots = project(_alternating(3));
      final outgoing = CatalogFarStitch.captureOutgoing(
        slots: slots,
        scrollOffset: 0,
        viewportHeight: 400,
      );
      // After the jump the viewport shows [488, 888): s1 and e2.
      final incoming = [
        for (final slot in slots)
          if (slot.bottom >= 616 && slot.top <= 1016) slot,
      ];

      final travel = CatalogFarStitch.measureTravel(
        outgoing: outgoing,
        incomingVisible: incoming,
        towardNewer: true,
        scrollOffset: 616,
        viewportHeight: 400,
      );

      expect(travel, greaterThan(0));
      expect(travel.isFinite, isTrue);
    });
  });

  group('the visible band', () {
    testWidgets('the settled keys are the cells in view, across layouts', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('emoji', 24),
        _section('stickers', 12, layout: _stickers, from: 100),
        _section('more', 16, from: 200),
        _section('tail', 64, from: 300),
      ]);
      await pump(tester);
      events.clear();

      controller.jumpTo(150);
      await tester.pump();
      await tester.pump();

      // [150, 550): the last emoji row (128..176), the sticker rows
      // (216..456) and both rows of `more` (488..584); `tail` starts at 584
      // below its header.
      final settled = events.whereType<PanelCatalogScrollSettled>().last;
      expect(settled.visibleKeys, [
        for (var i = 16; i < 24; i++) ContentKey.unicode(_glyph(i)),
        for (var i = 100; i < 112; i++) ContentKey.unicode(_glyph(i)),
        for (var i = 200; i < 216; i++) ContentKey.unicode(_glyph(i)),
      ]);
    });

    testWidgets('bindings follow the band in a 5-column section', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section('emoji', 24),
        _section('stickers', 60, layout: _stickers, from: 100),
      ]);
      await pump(tester);
      final render = _render(tester);

      controller.jumpTo(render.maxOffset);
      await tester.pump();

      // The band is the last rows of the 5-column section: 400 / 80 = 5 rows
      // plus one row of overscan (48), at 5 columns.
      expect(render.attachedLeafCount, inInclusiveRange(25, 40));
    });
  });
}
