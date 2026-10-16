import 'dart:math' as math;

import 'package:flutter/painting.dart' show TextDirection;
import 'package:panel_catalog/src/model/catalog_section.dart';
import 'package:panel_catalog/src/viewport/catalog_focus.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// A leaf cell by position: the index of its section in the catalogue and its
/// index in that section's leaves.
typedef CatalogCell = ({int section, int index});

/// The first leaf of the catalogue, or null when no section has any.
CatalogCell? firstCatalogCell(List<CatalogSection> sections) {
  for (var s = 0; s < sections.length; s++) {
    if (sections[s].leaves.isNotEmpty) return (section: s, index: 0);
  }
  return null;
}

/// The last leaf of the catalogue, or null when no section has any.
CatalogCell? lastCatalogCell(List<CatalogSection> sections) {
  for (var s = sections.length - 1; s >= 0; s--) {
    final count = sections[s].leaves.length;
    if (count > 0) return (section: s, index: count - 1);
  }
  return null;
}

/// The cell roving focus lands on when [move] is made from [from], or null when
/// there is nowhere to go (the end of the catalogue, or a column with nothing
/// under it).
///
/// A pure function of the sections and the [bands] they were projected into, so
/// a column here is the column on screen: sections of different spans, cell
/// widths and directions stack, and a vertical move keeps the cell's **screen**
/// x. Sections without leaves (empty, loading, failed) hold no focus and are
/// stepped over; skeleton cells are not cells.
CatalogCell? moveCatalogFocus({
  required CatalogCell from,
  required CatalogFocusMove move,
  required List<CatalogSection> sections,
  required List<CatalogSectionBand> bands,
}) {
  switch (move) {
    case CatalogFocusMove.first:
      return firstCatalogCell(sections);
    case CatalogFocusMove.last:
      return lastCatalogCell(sections);
    case CatalogFocusMove.next:
      return _step(from, 1, sections);
    case CatalogFocusMove.previous:
      return _step(from, -1, sections);
    case CatalogFocusMove.right || CatalogFocusMove.left:
      final rtl = bands[from.section].grid.textDirection == TextDirection.rtl;
      final toward = move == CatalogFocusMove.right ? 1 : -1;
      return _step(from, rtl ? -toward : toward, sections);
    case CatalogFocusMove.down:
      return _vertical(from, 1, sections, bands);
    case CatalogFocusMove.up:
      return _vertical(from, -1, sections, bands);
  }
}

/// One cell along reading order, crossing into the neighbouring section that
/// has leaves.
CatalogCell? _step(CatalogCell from, int delta, List<CatalogSection> sections) {
  final index = from.index + delta;
  final count = sections[from.section].leaves.length;
  if (index >= 0 && index < count) return (section: from.section, index: index);
  for (
    var s = from.section + delta;
    s >= 0 && s < sections.length;
    s += delta
  ) {
    final leaves = sections[s].leaves.length;
    if (leaves == 0) continue;
    return (section: s, index: delta > 0 ? 0 : leaves - 1);
  }
  return null;
}

/// One row down ([delta] 1) or up (-1) at the cell's screen x.
CatalogCell? _vertical(
  CatalogCell from,
  int delta,
  List<CatalogSection> sections,
  List<CatalogSectionBand> bands,
) {
  final grid = bands[from.section].grid;
  final span = grid.spanCount;
  final count = sections[from.section].leaves.length;
  final row = from.index ~/ span + delta;
  if (row >= 0 && row * span < count) {
    // Same section: the same column (a short last row takes its last leaf).
    return (
      section: from.section,
      index: math.min(row * span + from.index % span, count - 1),
    );
  }
  final x = grid.cellLeft(from.index % span) + grid.cellWidth / 2;
  for (
    var s = from.section + delta;
    s >= 0 && s < sections.length;
    s += delta
  ) {
    final leaves = sections[s].leaves.length;
    if (leaves == 0) continue;
    final target = bands[s].grid;
    final targetRow = delta > 0 ? 0 : (leaves - 1) ~/ target.spanCount;
    return (
      section: s,
      index: math.min(
        targetRow * target.spanCount + target.columnAt(x),
        leaves - 1,
      ),
    );
  }
  return null;
}
