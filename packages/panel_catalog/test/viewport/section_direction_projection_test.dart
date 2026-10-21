/// Grid direction: where a cell sits in its row, as pure functions.
///
/// Direction changes the x of a slot and nothing else: rows, bands, extents
/// and the order of the slots in the projection are the same either way.
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
  TextDirection direction = TextDirection.ltr,
  EdgeInsets padding = EdgeInsets.zero,
}) => CatalogSlotProjection.project(
  sections: sections,
  spanCount: 8,
  cellExtent: 48,
  headerExtent: 32,
  padding: padding,
  maxWidth: 400,
  textDirection: direction,
);

List<CatalogLeafSlot> _leaves(CatalogSlotProjection p) => [
  for (final slot in p.slots)
    if (slot case final CatalogLeafSlot leaf) leaf,
];

void main() {
  group('cells order start to end', () {
    test('left to right in a left-to-right grid', () {
      final leaves = _leaves(_project([_section('a', 3)]));

      expect([for (final l in leaves) l.left], [0, 50, 100]);
    });

    test('right to left in a right-to-left grid', () {
      final leaves = _leaves(
        _project([_section('a', 3)], direction: TextDirection.rtl),
      );

      expect([for (final l in leaves) l.left], [350, 300, 250]);
    });

    test('a short last row starts at the same edge as the rows above', () {
      final leaves = _leaves(
        _project([_section('a', 10)], direction: TextDirection.rtl),
      );

      expect(leaves[8].left, 350);
      expect(leaves[9].left, 300);
      expect(leaves[8].top, leaves[9].top);
      expect(leaves[8].top, greaterThan(leaves[0].top));
    });

    test('padding and section insets stay on their physical side', () {
      final leaves = _leaves(
        _project(
          [
            _section(
              'a',
              2,
              layout: const SectionLayout.grid(
                spanCount: 4,
                insets: EdgeInsets.only(left: 8, right: 16),
              ),
            ),
          ],
          direction: TextDirection.rtl,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      );

      // Usable 400 - 20 - 24 = 356, four cells of 89 from x = 18.
      expect(leaves[0].left, closeTo(18 + 3 * 89, 1e-9));
      expect(leaves[1].left, closeTo(18 + 2 * 89, 1e-9));
    });
  });

  group('direction changes x and nothing else', () {
    test('rows, extents and slot order match the other direction', () {
      final sections = [_section('a', 20), _section('b', 5)];
      final ltr = _project(sections);
      final rtl = _project(sections, direction: TextDirection.rtl);

      expect(rtl.contentExtent, ltr.contentExtent);
      expect(rtl.slots.length, ltr.slots.length);
      for (var i = 0; i < ltr.slots.length; i++) {
        expect(rtl.slots[i].top, ltr.slots[i].top);
        expect(rtl.slots[i].height, ltr.slots[i].height);
        expect(rtl.slots[i].runtimeType, ltr.slots[i].runtimeType);
      }
    });

    test('a leaf mirrors about the centre of its section', () {
      final ltr = _leaves(_project([_section('a', 20)]));
      final rtl = _leaves(
        _project([_section('a', 20)], direction: TextDirection.rtl),
      );

      for (var i = 0; i < ltr.length; i++) {
        expect(rtl[i].left + ltr[i].left + ltr[i].width, closeTo(400, 1e-9));
      }
    });
  });

  group('a section can state its own direction', () {
    test('a right-to-left section in a left-to-right catalog', () {
      final leaves = _leaves(
        _project([
          _section(
            'a',
            2,
            layout: const SectionLayout.grid(textDirection: TextDirection.rtl),
          ),
          _section('b', 2),
        ]),
      );

      expect([for (final l in leaves) l.left], [350, 300, 0, 50]);
    });

    test('a left-to-right section in a right-to-left catalog', () {
      final leaves = _leaves(
        _project([
          _section(
            'a',
            2,
            layout: const SectionLayout.grid(textDirection: TextDirection.ltr),
          ),
          _section('b', 2),
        ], direction: TextDirection.rtl),
      );

      expect([for (final l in leaves) l.left], [0, 50, 350, 300]);
    });

    test('headers carry the direction of their section', () {
      final p = _project([
        _section(
          'a',
          1,
          layout: const SectionLayout.grid(textDirection: TextDirection.rtl),
        ),
        _section('b', 1),
      ]);
      final headers = p.slots.whereType<CatalogHeaderSlot>().toList();

      expect(headers[0].textDirection, TextDirection.rtl);
      expect(headers[1].textDirection, TextDirection.ltr);
    });

    test('layouts differing only in direction are not equal', () {
      expect(
        const SectionLayout.grid(textDirection: TextDirection.rtl),
        isNot(const SectionLayout.grid()),
      );
      expect(
        const SectionLayout.grid(textDirection: TextDirection.rtl),
        const SectionLayout.grid(textDirection: TextDirection.rtl),
      );
    });
  });
}
