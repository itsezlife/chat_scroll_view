import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Max flat-row distance for near-path section jumps.
///
/// Panel catalogs index sections as **flat rows** (one slot per section header
/// plus one per leaf row at the section's own column count). A common per-cell
/// adapter gate of `spanCount × 9` cells maps to **`9` flat rows** —
/// multiplying the flat-row delta by the span again over-widens near-path
/// selection.
const int kFarPathDistanceGateFactor = 9;

/// Scroll offset that parks [sectionIndex]'s header under the landing inset.
///
/// Content paints with `viewportY = contentY − offset`, so
/// `offset = headerTop − landingInset` aligns the header with the reserved top
/// band. When [headerLandingInset] is null, [padding.top] is used.
///
/// Each section is laid out by its own [CatalogSection.layout] against the
/// viewport defaults [spanCount], [cellExtent] and [headerExtent] at
/// [maxWidth], so the offset is the header of the section as painted, whatever
/// the sections above it look like. Empty sections still reserve their header
/// extent, so landing on one is valid.
double scrollOffsetForSectionHeader({
  required int sectionIndex,
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  required double maxWidth,
  double? headerLandingInset,
}) {
  final bands = projectCatalogSectionBands(
    sections: sections,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: headerExtent,
    padding: padding,
    maxWidth: maxWidth,
  ).bands;
  return scrollOffsetForBand(
    bands[sectionIndex],
    landingInset: headerLandingInset ?? padding.top,
  );
}

/// [scrollOffsetForSectionHeader] for an already projected [band].
double scrollOffsetForBand(
  CatalogSectionBand band, {
  required double landingInset,
}) => math.max(0, band.headerTop - landingInset);

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
/// Same header + row geometry as [projectCatalogSlots], read from [bands]: the
/// sections wholly above the viewport are skipped by binary search and the row
/// is computed inside the section it falls in, so the cost does not grow with
/// the rows above. When the viewport is entirely below the catalog tail,
/// returns the last flat index; when it lies in space no row occupies (a
/// section inset), the nearest index below it.
int firstVisibleFlatIndex({
  required double scrollOffset,
  required double viewportHeight,
  required List<CatalogSectionBand> bands,
}) {
  if (bands.isEmpty) return 0;
  final visibleBottom = scrollOffset + viewportHeight;

  // First band that does not end above the viewport top.
  var lo = 0;
  var hi = bands.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (bands[mid].bottom <= scrollOffset) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }

  for (var b = lo; b < bands.length; b++) {
    final band = bands[b];
    if (band.headerTop + band.headerExtent > scrollOffset) {
      return band.flatIndex;
    }
    if (band.rowCount > 0 && band.rowExtent > 0) {
      final row = ((scrollOffset - band.rowsTop) / band.rowExtent)
          .floor()
          .clamp(0, band.rowCount);
      if (row < band.rowCount) {
        return band.flatIndex + 1 + row;
      }
    }
    if (band.headerTop >= visibleBottom) return band.flatIndex;
  }
  return bands.last.lastFlatIndex;
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
/// When the header is not visible, compares flat-row indices of the target
/// header and [firstVisibleFlatIndex] over [bands]:
/// `|targetFlat − firstVisibleFlat| ≤ [distanceGateFactor]` (default
/// [kFarPathDistanceGateFactor]). A section's rows are counted at its own
/// column count; the gate is **not** `spanCount × distanceGateFactor` rows.
///
/// When `false`, the bound viewport uses far-path stitch — not bare
/// [PanelCatalogController.jumpTo].
bool isNearPathSectionJump({
  required int targetSectionIndex,
  required List<CatalogSectionBand> bands,
  required double scrollOffset,
  required double viewportHeight,
  int distanceGateFactor = kFarPathDistanceGateFactor,
}) {
  final target = bands[targetSectionIndex];
  if (isSectionHeaderVisible(
    headerTop: target.headerTop,
    headerExtent: target.headerExtent,
    scrollOffset: scrollOffset,
    viewportHeight: viewportHeight,
  )) {
    return true;
  }

  final firstVisible = firstVisibleFlatIndex(
    scrollOffset: scrollOffset,
    viewportHeight: viewportHeight,
    bands: bands,
  );
  return (target.flatIndex - firstVisible).abs() <= distanceGateFactor;
}
