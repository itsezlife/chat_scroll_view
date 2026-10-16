/// Where roving focus goes: a move from one cell to the next across rows,
/// sections and directions, as a pure function of the projected catalogue.
///
/// Viewport defaults: 4 columns of 100 px cells in 400 px. Sections lay
/// themselves out through the same projection the viewport paints with, so a
/// column here is the column on screen.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_focus_navigation.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

CatalogSection _section(
  String id,
  int leaves, {
  int? span,
  TextDirection? direction,
}) => CatalogSection(
  id: id,
  title: id,
  layout: span == null && direction == null
      ? null
      : SectionLayout.grid(spanCount: span, textDirection: direction),
  leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode('$id$i')],
);

CatalogCell? _move(
  List<CatalogSection> sections,
  CatalogCell from,
  CatalogFocusMove move, {
  TextDirection direction = TextDirection.ltr,
}) => moveCatalogFocus(
  from: from,
  move: move,
  sections: sections,
  bands: projectCatalogSectionBands(
    sections: sections,
    spanCount: 4,
    cellExtent: 100,
    headerExtent: 20,
    padding: EdgeInsets.zero,
    maxWidth: 400,
    textDirection: direction,
  ).bands,
);

// 10 leaves in 4 columns: rows of 4, 4 and 2.
final _a = _section('a', 10);

void main() {
  group('along a row', () {
    test('right and left step through the leaves of a left-to-right grid', () {
      expect(_move([_a], (section: 0, index: 1), CatalogFocusMove.right), (
        section: 0,
        index: 2,
      ));
      expect(_move([_a], (section: 0, index: 1), CatalogFocusMove.left), (
        section: 0,
        index: 0,
      ));
    });

    test('left steps forward in a right-to-left grid', () {
      expect(
        _move(
          [_a],
          (section: 0, index: 1),
          CatalogFocusMove.left,
          direction: TextDirection.rtl,
        ),
        (section: 0, index: 2),
      );
      expect(
        _move(
          [_a],
          (section: 0, index: 1),
          CatalogFocusMove.right,
          direction: TextDirection.rtl,
        ),
        (section: 0, index: 0),
      );
    });

    test('the end of a row continues on the start of the next', () {
      expect(_move([_a], (section: 0, index: 3), CatalogFocusMove.right), (
        section: 0,
        index: 4,
      ));
      expect(_move([_a], (section: 0, index: 4), CatalogFocusMove.left), (
        section: 0,
        index: 3,
      ));
    });

    test('next and previous follow reading order whatever the direction', () {
      for (final direction in TextDirection.values) {
        expect(
          _move(
            [_a],
            (section: 0, index: 1),
            CatalogFocusMove.next,
            direction: direction,
          ),
          (section: 0, index: 2),
        );
        expect(
          _move(
            [_a],
            (section: 0, index: 1),
            CatalogFocusMove.previous,
            direction: direction,
          ),
          (section: 0, index: 0),
        );
      }
    });
  });

  group('across sections', () {
    final sections = [_a, _section('empty', 0), _section('b', 3)];

    test('the last leaf continues in the first of the next section', () {
      expect(_move(sections, (section: 0, index: 9), CatalogFocusMove.next), (
        section: 2,
        index: 0,
      ));
    });

    test('the first leaf goes back to the last of the previous section', () {
      expect(
        _move(sections, (section: 2, index: 0), CatalogFocusMove.previous),
        (section: 0, index: 9),
      );
    });

    test('the ends of the catalogue stay put', () {
      expect(
        _move(sections, (section: 2, index: 2), CatalogFocusMove.next),
        isNull,
      );
      expect(
        _move(sections, (section: 0, index: 0), CatalogFocusMove.previous),
        isNull,
      );
    });
  });

  group('down and up', () {
    test('keep the column inside a section', () {
      expect(_move([_a], (section: 0, index: 1), CatalogFocusMove.down), (
        section: 0,
        index: 5,
      ));
      expect(_move([_a], (section: 0, index: 5), CatalogFocusMove.up), (
        section: 0,
        index: 1,
      ));
    });

    test('a short last row takes its last leaf', () {
      // Row 2 has columns 0 and 1 only.
      expect(_move([_a], (section: 0, index: 7), CatalogFocusMove.down), (
        section: 0,
        index: 9,
      ));
    });

    test('down from the last row enters the first row of the next section', () {
      final sections = [_a, _section('b', 8)];

      expect(_move(sections, (section: 0, index: 8), CatalogFocusMove.down), (
        section: 1,
        index: 0,
      ));
      expect(_move(sections, (section: 0, index: 9), CatalogFocusMove.down), (
        section: 1,
        index: 1,
      ));
    });

    test('up from the first row enters the last row of the previous one', () {
      final sections = [_a, _section('b', 8)];

      // Column 2 of b's first row: a's last row has only columns 0 and 1.
      expect(_move(sections, (section: 1, index: 2), CatalogFocusMove.up), (
        section: 0,
        index: 9,
      ));
      expect(_move(sections, (section: 1, index: 1), CatalogFocusMove.up), (
        section: 0,
        index: 9,
      ));
      expect(_move(sections, (section: 1, index: 0), CatalogFocusMove.up), (
        section: 0,
        index: 8,
      ));
    });

    test('keep the screen column across sections of different spans', () {
      // b has two columns of 200: the cell under a's column 3 is its second.
      final sections = [_section('a', 8), _section('b', 4, span: 2)];

      expect(_move(sections, (section: 0, index: 7), CatalogFocusMove.down), (
        section: 1,
        index: 1,
      ));
      expect(_move(sections, (section: 0, index: 4), CatalogFocusMove.down), (
        section: 1,
        index: 0,
      ));
    });

    test('keep the screen column in a right-to-left grid', () {
      final sections = [_section('a', 8), _section('b', 4, span: 2)];

      // Column 0 of a is at the right edge, over b's first cell (the right).
      expect(
        _move(
          sections,
          (section: 0, index: 4),
          CatalogFocusMove.down,
          direction: TextDirection.rtl,
        ),
        (section: 1, index: 0),
      );
      // Column 3 of a is at the left edge, over b's second.
      expect(
        _move(
          sections,
          (section: 0, index: 7),
          CatalogFocusMove.down,
          direction: TextDirection.rtl,
        ),
        (section: 1, index: 1),
      );
    });

    test('the ends of the catalogue stay put', () {
      expect(
        _move([_a], (section: 0, index: 9), CatalogFocusMove.down),
        isNull,
        reason: 'no row below the last',
      );
      expect(
        _move([_a], (section: 0, index: 2), CatalogFocusMove.up),
        isNull,
        reason: 'no row above the first',
      );
    });
  });

  group('first and last', () {
    final sections = [_section('empty', 0), _a, _section('b', 3)];

    test('the first leaf skips sections with none', () {
      expect(firstCatalogCell(sections), (section: 1, index: 0));
    });

    test('the last leaf is the last of the last section with any', () {
      expect(lastCatalogCell(sections), (section: 2, index: 2));
      expect(lastCatalogCell([_a, _section('empty', 0)]), (
        section: 0,
        index: 9,
      ));
    });

    test('an empty catalogue has neither', () {
      expect(firstCatalogCell([_section('empty', 0)]), isNull);
      expect(lastCatalogCell(const []), isNull);
    });

    test('first and last moves go there from anywhere', () {
      expect(_move(sections, (section: 2, index: 1), CatalogFocusMove.first), (
        section: 1,
        index: 0,
      ));
      expect(_move(sections, (section: 1, index: 4), CatalogFocusMove.last), (
        section: 2,
        index: 2,
      ));
    });
  });
}
