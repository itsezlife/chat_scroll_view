/// Per-section layout: slot projection, extent math, section landing and the
/// near / far gate, as pure functions (no widgets).
///
/// Viewport defaults throughout: 8 columns, 48 cell, 32 header, 400 wide.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

CatalogSection _section(String id, int leaves, {SectionLayout? layout}) =>
    CatalogSection(
      id: id,
      title: 'Section $id',
      layout: layout,
      leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode('$id$i')],
    );

CatalogSlotProjection _project(
  List<CatalogSection> sections, {
  EdgeInsets padding = EdgeInsets.zero,
  double maxWidth = 400,
}) => CatalogSlotProjection.project(
  sections: sections,
  spanCount: 8,
  cellExtent: 48,
  headerExtent: 32,
  padding: padding,
  maxWidth: maxWidth,
);

List<CatalogSectionBand> _bands(List<CatalogSection> sections) =>
    CatalogSectionBands.project(
      sections: sections,
      spanCount: 8,
      cellExtent: 48,
      headerExtent: 32,
      padding: EdgeInsets.zero,
      maxWidth: 400,
    ).bands;

List<CatalogLeafSlot> _leafSlots(CatalogSlotProjection p, String sectionId) => [
  for (final slot in p.slots)
    if (slot case final CatalogLeafSlot leaf when leaf.sectionId == sectionId)
      leaf,
];

/// 8 columns (defaults) / 5 columns with a taller cell and header / defaults.
final _mixed = [
  _section('a', 20),
  _section(
    'b',
    12,
    layout: const SectionLayout.grid(
      spanCount: 5,
      cellExtent: 80,
      headerExtent: 40,
    ),
  ),
  _section('c', 9),
];

void main() {
  group('slot projection with per-section layouts', () {
    test('a section without a layout is laid out by the viewport defaults', () {
      final p = _project([_section('a', 20)]);

      // header 32 + 3 rows of 48
      expect(p.contentExtent, 32 + 3 * 48);
      final slots = _leafSlots(p, 'a');
      expect(slots[9].top, 32 + 48);
      expect(slots[9].left, 1 * 50);
      expect(slots[9].width, 50);
      expect(slots[9].height, 48);
    });

    test('sections with different spans stack with their own geometry', () {
      final p = _project(_mixed);

      // a: 0..176 (header 32 + 3 rows of 48); b: header 40 + 3 rows of 80;
      // c: header 32 + 2 rows of 48.
      expect(p.contentExtent, 176 + (40 + 3 * 80) + (32 + 2 * 48));

      final headers = p.slots.whereType<CatalogHeaderSlot>().toList();
      expect([for (final h in headers) h.top], [0, 176, 176 + 280]);
      expect([for (final h in headers) h.height], [32, 40, 32]);

      final b = _leafSlots(p, 'b');
      expect(b, hasLength(12));
      // index 7 → row 1, column 2 of 5 columns at 80 wide.
      expect(b[7].index, 7);
      expect(b[7].top, 176 + 40 + 80);
      expect(b[7].left, 160);
      expect(b[7].width, 80);
      expect(b[7].height, 80);

      final c = _leafSlots(p, 'c');
      expect(c.first.top, 176 + 280 + 32);
      expect(c.first.width, 50);
    });

    test('slots stay in ascending order across layouts', () {
      final p = _project(_mixed);

      for (var i = 1; i < p.slots.length; i++) {
        expect(p.slots[i].top, greaterThanOrEqualTo(p.slots[i - 1].top));
        expect(p.slots[i].bottom, greaterThanOrEqualTo(p.slots[i - 1].bottom));
      }
    });

    test('viewport padding frames the content, section insets nest in it', () {
      final p = _project([
        _section(
          'a',
          9,
          layout: const SectionLayout.grid(
            insets: EdgeInsets.fromLTRB(10, 6, 10, 4),
          ),
        ),
      ], padding: const EdgeInsets.fromLTRB(8, 10, 8, 12));

      // usable width 400 - 16 - 20 = 364 over 8 columns
      final leaves = _leafSlots(p, 'a');
      expect(leaves[0].width, 364 / 8);
      expect(leaves[0].left, 8 + 10);
      expect(leaves[8].left, 8 + 10);
      final header = p.slots.whereType<CatalogHeaderSlot>().single;
      expect(header.top, 10 + 6);
      expect(header.left, 8 + 10);
      expect(header.width, 364);
      // top pad 10 + inset 6 + header 32 + 2 rows + inset 4 + bottom pad 12
      expect(p.contentExtent, 10 + 6 + 32 + 2 * 48 + 4 + 12);
    });

    test('a cell aspect derives the row height from the cell width', () {
      final p = _project([
        _section(
          'a',
          10,
          layout: const SectionLayout.grid(spanCount: 5, cellAspect: 1.25),
        ),
      ]);

      // 400 / 5 = 80 wide, 80 / 1.25 = 64 tall, 2 rows.
      final leaves = _leafSlots(p, 'a');
      expect(leaves[0].width, 80);
      expect(leaves[0].height, 64);
      expect(p.contentExtent, 32 + 2 * 64);
    });

    test('an empty section keeps its header and adds no row', () {
      final p = _project([
        _section('a', 0),
        _section(
          'b',
          3,
          layout: const SectionLayout.grid(spanCount: 5, headerExtent: 10),
        ),
      ]);

      expect(p.slots.whereType<CatalogHeaderSlot>().map((h) => h.top), [0, 32]);
      expect(p.contentExtent, 32 + 10 + 48);
    });

    test('a degenerate width falls back to the cell extent', () {
      final p = _project([_section('a', 3)], maxWidth: 0);

      final leaves = _leafSlots(p, 'a');
      expect(leaves[0].width, 48);
      expect(leaves[1].left, 48);
    });
  });

  group('section landing across sections with different spans', () {
    test('lands each header by the extents of the sections before it', () {
      double landing(int i, {double? inset}) =>
          CatalogSectionNavigation.scrollOffsetForSectionHeader(
            sectionIndex: i,
            sections: _mixed,
            spanCount: 8,
            cellExtent: 48,
            headerExtent: 32,
            padding: EdgeInsets.zero,
            maxWidth: 400,
            headerLandingInset: inset,
          );

      expect(landing(0), 0);
      expect(landing(1), 176);
      expect(landing(2), 176 + 280);
      expect(landing(2, inset: 30), 176 + 280 - 30);
    });

    test('the landing offset is the projected header top', () {
      final p = _project(_mixed, padding: const EdgeInsets.only(top: 14));
      final headers = p.slots.whereType<CatalogHeaderSlot>().toList();

      for (var i = 0; i < _mixed.length; i++) {
        expect(
          CatalogSectionNavigation.scrollOffsetForSectionHeader(
            sectionIndex: i,
            sections: _mixed,
            spanCount: 8,
            cellExtent: 48,
            headerExtent: 32,
            padding: const EdgeInsets.only(top: 14),
            maxWidth: 400,
            headerLandingInset: 0,
          ),
          headers[i].top,
        );
      }
    });

    test('the landing offset includes the section inset above the header', () {
      final sections = [
        _section('a', 8),
        _section(
          'b',
          8,
          layout: const SectionLayout.grid(insets: EdgeInsets.only(top: 12)),
        ),
      ];

      expect(
        CatalogSectionNavigation.scrollOffsetForSectionHeader(
          sectionIndex: 1,
          sections: sections,
          spanCount: 8,
          cellExtent: 48,
          headerExtent: 32,
          padding: EdgeInsets.zero,
          maxWidth: 400,
        ),
        32 + 48 + 12,
      );
    });
  });

  group('near / far gate across sections with different spans', () {
    bool near(
      List<CatalogSection> sections,
      int target, {
      double scroll = 0,
      double viewport = 50,
    }) => CatalogSectionNavigation.isNearPathSectionJump(
      targetSectionIndex: target,
      bands: _bands(sections),
      scrollOffset: scroll,
      viewportHeight: viewport,
    );

    test('counts the rows of each section at its own span', () {
      const five = SectionLayout.grid(spanCount: 5);
      // 40 leaves at 5 columns are 8 rows: the target header is flat index 9,
      // nine away from the first visible header: still near.
      expect(
        near([_section('x', 40, layout: five), _section('t', 1)], 1),
        true,
      );
      // 45 leaves are 9 rows: ten away, so far. At the viewport's 8 columns
      // the same leaves are 6 rows and the jump would wrongly be near.
      expect(
        near([_section('x', 45, layout: five), _section('t', 1)], 1),
        false,
      );
      expect(near([_section('x', 45), _section('t', 1)], 1), true);
    });

    test('a target header in the viewport is always near', () {
      expect(near(_mixed, 1, scroll: 100, viewport: 300), true);
    });

    test('measures the first visible row from the section it falls in', () {
      final sections = [
        _section('x', 100, layout: const SectionLayout.grid(spanCount: 5)),
        _section('y', 100, layout: const SectionLayout.grid(spanCount: 5)),
        _section('t', 1),
      ];
      // Scrolled to y's first rows: x is 20 rows (21 flat), y is 20 rows.
      // y header at 32 + 20 * 48 = 992; the viewport at 1100 shows its row 1.
      final first = CatalogSectionNavigation.firstVisibleFlatIndex(
        scrollOffset: 1100,
        viewportHeight: 100,
        bands: _bands(sections),
      );
      // 21 flat indices of x, y's header, then y's row 1 is at the viewport top.
      expect(first, 21 + 1 + 1);
      expect(near(sections, 2, scroll: 1100, viewport: 100), false);
    });
  });

  group('first visible flat index', () {
    test('matches a walk over the projected slots at every offset', () {
      final sections = [
        ..._mixed,
        _section('d', 0),
        for (var i = 0; i < 6; i++)
          _section(
            'x$i',
            5 + i * 7,
            layout: i.isOdd ? const SectionLayout.grid(spanCount: 5) : null,
          ),
      ];
      final projection = CatalogSlotProjection.project(
        sections: sections,
        spanCount: 8,
        cellExtent: 48,
        headerExtent: 32,
        padding: EdgeInsets.zero,
        maxWidth: 400,
      );
      // One flat item per header and per distinct leaf row, from the slots.
      final items = <(double top, double bottom)>[];
      for (final slot in projection.slots) {
        final isNewItem = switch (slot) {
          CatalogHeaderSlot() => true,
          CatalogSkeletonSlot() || CatalogMessageSlot() => true,
          CatalogLeafSlot() =>
            items.isEmpty ||
                items.last.$1 != slot.top ||
                items.last.$2 != slot.bottom,
        };
        if (isNewItem) items.add((slot.top, slot.bottom));
      }
      int walk(double scroll, double viewport) {
        for (var i = 0; i < items.length; i++) {
          if (items[i].$2 > scroll && items[i].$1 < scroll + viewport) return i;
        }
        return items.length - 1;
      }

      final bands = projection.bands;
      for (
        var scroll = 0.0;
        scroll < projection.contentExtent + 200;
        scroll += 7
      ) {
        expect(
          CatalogSectionNavigation.firstVisibleFlatIndex(
            scrollOffset: scroll,
            viewportHeight: 100,
            bands: bands,
          ),
          walk(scroll, 100),
          reason: 'scroll $scroll',
        );
      }
    });
  });

  group('largest glyph box', () {
    double largest(Iterable<SectionLayout?> layouts, {double maxWidth = 400}) =>
        PanelCatalogViewport.largestGlyphBox(
          layouts: layouts,
          spanCount: 8,
          cellExtent: 48,
          padding: EdgeInsets.zero,
          maxWidth: maxWidth,
        );

    test('is the biggest box any section draws a glyph in', () {
      // 8 columns: 50 x 48 cells → 48; 5 columns at 80: 80 x 80 → 80.
      expect(largest([null]), 48 * CatalogContentBox.glyphBoxFraction);
      expect(
        largest([null, const SectionLayout.grid(spanCount: 5, cellExtent: 80)]),
        80 * CatalogContentBox.glyphBoxFraction,
      );
    });

    test('takes the shorter side of a cell, so a wide cell is not larger', () {
      // 2 columns: 200 x 48 cells; the box follows the 48 side.
      expect(
        largest([const SectionLayout.grid(spanCount: 2)]),
        48 * CatalogContentBox.glyphBoxFraction,
      );
    });

    test('with no section it is the viewport default', () {
      expect(largest(const []), 48 * CatalogContentBox.glyphBoxFraction);
    });

    test('is the box the painter draws in', () {
      final slot = _leafSlots(_project(_mixed), 'b').first;

      expect(
        CatalogContentBox.glyphBoxExtent(slot.width, slot.height),
        largest(_mixed.map((s) => s.layout)),
      );
    });

    test('accounts for the insets a section takes from the width', () {
      // 8 columns in 400 - 160 = 240 → 30 wide cells; box follows the width.
      expect(
        largest([
          const SectionLayout.grid(
            insets: EdgeInsets.symmetric(horizontal: 80),
          ),
        ]),
        30 * CatalogContentBox.glyphBoxFraction,
      );
    });
  });

  group('section states in the projection', () {
    test('skeleton cells continue the grid after the leaves', () {
      final p = _project([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [for (var i = 0; i < 6; i++) CatalogLeaf.unicode('a$i')],
          state: CatalogSectionState.loading,
          skeletonCount: 5,
        ),
      ]);

      final skeletons = p.slots.whereType<CatalogSkeletonSlot>().toList();
      expect(skeletons, hasLength(5));
      // 8 columns of 50: cells 6 and 7 finish row 0, cells 8..10 start row 1.
      expect(skeletons.map((s) => s.left), [300, 350, 0, 50, 100]);
      expect(skeletons.map((s) => s.top), [32, 32, 80, 80, 80]);
      expect(p.contentExtent, 32 + 2 * 48);
    });

    test(
      'a loading section adds the rows of its skeletons to the flat index',
      () {
        final bands = _bands([
          const CatalogSection(
            id: 'a',
            title: 'A',
            leaves: [],
            state: CatalogSectionState.loading,
            skeletonCount: 17,
          ),
          _section('b', 1),
        ]);

        // 17 skeletons at 8 columns are 3 rows: header + 3 rows, then b.
        expect(bands[0].rowCount, 3);
        expect(bands[1].flatIndex, 4);
      },
    );

    test('the message row takes one row across the usable width', () {
      final p = _project([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          emptyMessage: 'None',
        ),
      ], padding: const EdgeInsets.symmetric(horizontal: 10));

      final message = p.slots.whereType<CatalogMessageSlot>().single;
      expect(message.top, 32);
      expect(message.height, 48);
      expect(message.left, 10);
      expect(message.width, 380);
      expect(p.contentExtent, 32 + 48);
    });

    test('the header slot carries its section and action', () {
      const action = CatalogSectionAction(id: 'more', label: 'More');
      final p = _project([
        const CatalogSection(id: 'a', title: 'A', leaves: [], action: action),
      ]);

      final header = p.slots.whereType<CatalogHeaderSlot>().single;
      expect(header.sectionId, 'a');
      expect(header.action, action);
    });

    test('slots of all kinds stay in ascending order', () {
      final p = _project([
        const CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [],
          state: CatalogSectionState.failed,
          skeletonCount: 20,
        ),
        const CatalogSection(
          id: 'b',
          title: 'B',
          leaves: [],
          emptyMessage: 'None',
        ),
        _section('c', 30),
      ]);

      for (var i = 1; i < p.slots.length; i++) {
        expect(p.slots[i].top, greaterThanOrEqualTo(p.slots[i - 1].top));
        expect(p.slots[i].bottom, greaterThanOrEqualTo(p.slots[i - 1].bottom));
      }
    });
  });
}
