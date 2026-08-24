import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// Flat-row distance multiplier for near vs far path selection.
///
/// Near path when the target section header is visible or
/// `|targetFlatIndex − firstVisibleFlatIndex| ≤ spanCount × [kFarPathDistanceGateFactor]`.
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

/// Scroll offset that parks [sectionIndex]'s header under [padding.top].
///
/// Content paints with `viewportY = contentY − offset`, so
/// `offset = headerTop − padding.top` aligns the header with the reserved top
/// inset band used by the category strip shell.
double scrollOffsetForSectionHeader({
  required int sectionIndex,
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
}) {
  final headerTop = sectionHeaderTop(
    sectionIndex: sectionIndex,
    sections: sections,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: headerExtent,
    padding: padding,
  );
  return math.max(0, headerTop - padding.top);
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

/// Near-path gate: attached target header or within `span × 9` flat-row distance.
///
/// When `false`, callers should use far-path navigation (stitch — not bare
/// [PanelCatalogController.jumpTo] as the default UX).
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
  return rowDelta <= spanCount * distanceGateFactor;
}
