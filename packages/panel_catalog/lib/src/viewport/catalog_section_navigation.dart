import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// Max flat-row distance for near-path section jumps.
///
/// Panel catalogs index sections as **flat rows** (one slot per section header
/// plus one per leaf row at [spanCount] columns). A common per-cell adapter
/// gate of `spanCount × 9` cells maps to **`9` flat rows** — multiplying the
/// flat-row delta by [spanCount] again over-widens near-path selection.
const int kFarPathDistanceGateFactor = 9;

/// Row count for [section]'s leaf grid at [spanCount] columns.
int catalogSectionRowCount(CatalogSection section, int spanCount) {
  final n = section.leaves.length;
  if (n == 0) return 0;
  return (n + spanCount - 1) ~/ spanCount;
}

/// Flat adapter index of [sectionIndex]'s header (one index per header + row).
///
/// Each section contributes one header index, then one index per leaf row
/// (not per cell).
int flatIndexForSectionHeader(
  int sectionIndex,
  List<CatalogSection> sections,
  int spanCount,
) {
  var index = 0;
  for (var s = 0; s < sectionIndex; s++) {
    index += 1 + catalogSectionRowCount(sections[s], spanCount);
  }
  return index;
}

/// Content-y of [sectionIndex]'s header top edge (before scrolling).
///
/// Empty sections still reserve [headerExtent]; their header top is valid for
/// strip landing even with no leaf rows below.
double sectionHeaderTop({
  required int sectionIndex,
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
}) {
  var y = padding.top;
  for (var s = 0; s < sectionIndex; s++) {
    y += headerExtent;
    y += catalogSectionRowCount(sections[s], spanCount) * cellExtent;
  }
  return y;
}

/// Scroll offset that parks [sectionIndex]'s header under the landing inset.
///
/// Content paints with `viewportY = contentY − offset`, so
/// `offset = headerTop − landingInset` aligns the header with the reserved top
/// band. When [headerLandingInset] is null, [padding.top] is used.
double scrollOffsetForSectionHeader({
  required int sectionIndex,
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  double? headerLandingInset,
}) {
  final headerTop = sectionHeaderTop(
    sectionIndex: sectionIndex,
    sections: sections,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: headerExtent,
    padding: padding,
  );
  final inset = headerLandingInset ?? padding.top;
  return math.max(0, headerTop - inset);
}

/// Whether [headerTop]…[headerTop]+[headerExtent] intersects the viewport band.
///
/// `scrollOffset` is the current content offset; the viewport shows
/// `[scrollOffset, scrollOffset + viewportHeight)`.
bool isSectionHeaderVisible({
  required double headerTop,
  required double headerExtent,
  required double scrollOffset,
  required double viewportHeight,
}) {
  final headerBottom = headerTop + headerExtent;
  final visibleBottom = scrollOffset + viewportHeight;
  return headerBottom > scrollOffset && headerTop < visibleBottom;
}

/// First flat adapter index with any part visible at [scrollOffset].
///
/// Walks the same header + row geometry as [projectCatalogSlots]. When the
/// viewport is entirely below the catalog tail, returns the last flat index.
int firstVisibleFlatIndex({
  required double scrollOffset,
  required double viewportHeight,
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
}) {
  if (sections.isEmpty) return 0;

  var y = padding.top;
  var flatIndex = 0;
  final visibleBottom = scrollOffset + viewportHeight;

  for (final section in sections) {
    if (y + headerExtent > scrollOffset && y < visibleBottom) {
      return flatIndex;
    }
    flatIndex += 1;
    y += headerExtent;

    final rowCount = catalogSectionRowCount(section, spanCount);
    for (var row = 0; row < rowCount; row++) {
      if (y + cellExtent > scrollOffset && y < visibleBottom) {
        return flatIndex;
      }
      flatIndex += 1;
      y += cellExtent;
    }
  }
  return math.max(0, flatIndex - 1);
}

/// Near-path gate for [PanelCatalogController.jumpToSection] path selection.
///
/// Returns `true` when the viewport SHOULD smooth-scroll (near path) rather
/// than stitch (far path).
///
/// ## Attached shortcut
///
/// `true` when [targetSectionIndex]'s header band intersects the viewport
/// (`[scrollOffset, scrollOffset + viewportHeight)` in content-y) — equivalent
/// to an attached target view in adapter-backed lists.
///
/// ## Distance gate
///
/// When the header is not visible, compares flat-row indices from
/// [flatIndexForSectionHeader] and [firstVisibleFlatIndex]:
/// `|targetFlat − firstVisibleFlat| ≤ [distanceGateFactor]` (default
/// [kFarPathDistanceGateFactor]). Each flat row spans up to [spanCount] leaf
/// cells; the gate is **not** `spanCount × distanceGateFactor` rows.
///
/// When `false`, the bound viewport uses far-path stitch — not bare
/// [PanelCatalogController.jumpTo].
bool isNearPathSectionJump({
  required int targetSectionIndex,
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  required double scrollOffset,
  required double viewportHeight,
  int distanceGateFactor = kFarPathDistanceGateFactor,
}) {
  final headerTop = sectionHeaderTop(
    sectionIndex: targetSectionIndex,
    sections: sections,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: headerExtent,
    padding: padding,
  );
  if (isSectionHeaderVisible(
    headerTop: headerTop,
    headerExtent: headerExtent,
    scrollOffset: scrollOffset,
    viewportHeight: viewportHeight,
  )) {
    return true;
  }

  final targetFlat = flatIndexForSectionHeader(
    targetSectionIndex,
    sections,
    spanCount,
  );
  final firstVisible = firstVisibleFlatIndex(
    scrollOffset: scrollOffset,
    viewportHeight: viewportHeight,
    sections: sections,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: headerExtent,
    padding: padding,
  );
  final rowDelta = (targetFlat - firstVisible).abs();
  return rowDelta <= distanceGateFactor;
}
