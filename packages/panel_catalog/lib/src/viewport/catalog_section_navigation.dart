import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Section landing and the near / far gate of a section jump: where a jump
/// parks a header, which section the viewport is in, and whether a jump
/// smooth-scrolls or stitches.
///
/// Hosts read [scrollOffsetForSectionHeader] and [farPathDistanceGateFactor];
/// the members that work on projected [CatalogSectionBand]s are the
/// viewport's own.
abstract final class CatalogSectionNavigation {
  /// Max flat-row distance for near-path section jumps.
  ///
  /// Panel catalogs index sections as **flat rows** (one slot per section
  /// header plus one per leaf row at the section's own column count). A common
  /// per-cell adapter gate of `spanCount × 9` cells maps to **`9` flat rows**
  /// — multiplying the flat-row delta by the span again over-widens near-path
  /// selection.
  static const int farPathDistanceGateFactor = 9;

  /// Scroll offset that parks [sectionIndex]'s header under the landing inset.
  ///
  /// Content paints with `viewportY = contentY − offset`, so
  /// `offset = headerTop − landingInset` aligns the header with the reserved
  /// top band. When [headerLandingInset] is null, [padding.top] is used.
  ///
  /// Each section is laid out by its own [CatalogSection.layout] against the
  /// viewport defaults [spanCount], [cellExtent] and [headerExtent] at
  /// [maxWidth], so the offset is the header of the section as painted,
  /// whatever the sections above it look like. Empty sections still reserve
  /// their header extent, so landing on one is valid.
  static double scrollOffsetForSectionHeader({
    required int sectionIndex,
    required List<CatalogSection> sections,
    required int spanCount,
    required double cellExtent,
    required double headerExtent,
    required EdgeInsets padding,
    required double maxWidth,
    double? headerLandingInset,
  }) {
    final bands = CatalogSectionBands.project(
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
  @internal
  static double scrollOffsetForBand(
    CatalogSectionBand band, {
    required double landingInset,
  }) => math.max(0, band.headerTop - landingInset);

  /// The index of the section the viewport at [offset] is in, or null for no
  /// [bands].
  ///
  /// A section is current from the moment its header reaches the line
  /// [landingInset] below the viewport top until the next one does; before the
  /// first header reaches it, the first section is. At the end of content that
  /// scrolls ([offset] at [maxScrollExtent], above zero) the last section is
  /// current when its header is in view: a section too short to bring its
  /// header to the line is still where a jump to it lands. [bands] are
  /// ascending, so the search is binary.
  @internal
  static int? currentSectionIndex(
    List<CatalogSectionBand> bands, {
    required double offset,
    required double landingInset,
    required double viewportHeight,
    required double maxScrollExtent,
  }) {
    if (bands.isEmpty) return null;
    final last = bands.length - 1;
    if (maxScrollExtent > 0.5 &&
        offset >= maxScrollExtent - 0.5 &&
        bands[last].headerTop < offset + viewportHeight) {
      return last;
    }
    final line = offset + landingInset + 0.5;
    var lo = 0;
    var hi = last;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (bands[mid].headerTop <= line) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Whether [headerTop]…[headerTop]+[headerExtent] intersects the viewport
  /// band.
  ///
  /// `scrollOffset` is the current content offset; the viewport shows
  /// `[scrollOffset, scrollOffset + viewportHeight)`.
  static bool _isSectionHeaderVisible({
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
  /// Same header + row geometry as [CatalogSlotProjection.project], read from
  /// [bands]: the sections wholly above the viewport are skipped by binary
  /// search and the row is computed inside the section it falls in, so the
  /// cost does not grow with the rows above. When the viewport is entirely
  /// below the catalog tail, returns the last flat index; when it lies in
  /// space no row occupies (a section inset), the nearest index below it.
  @internal
  static int firstVisibleFlatIndex({
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
  /// (`[scrollOffset, scrollOffset + viewportHeight)` in content-y) —
  /// equivalent to an attached target view in adapter-backed lists.
  ///
  /// ## Distance gate
  ///
  /// When the header is not visible, compares flat-row indices of the target
  /// header and [firstVisibleFlatIndex] over [bands]:
  /// `|targetFlat − firstVisibleFlat| ≤ [distanceGateFactor]` (default
  /// [farPathDistanceGateFactor]). A section's rows are counted at its own
  /// column count; the gate is **not** `spanCount × distanceGateFactor` rows.
  ///
  /// When `false`, the bound viewport uses far-path stitch — not bare
  /// [PanelCatalogController.jumpTo].
  @internal
  static bool isNearPathSectionJump({
    required int targetSectionIndex,
    required List<CatalogSectionBand> bands,
    required double scrollOffset,
    required double viewportHeight,
    int distanceGateFactor = farPathDistanceGateFactor,
  }) {
    final target = bands[targetSectionIndex];
    if (_isSectionHeaderVisible(
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

  /// The offset that brings the content-y span [top]..[bottom] into a
  /// viewport of [viewportHeight] currently at [pixels], moving as little as
  /// possible.
  ///
  /// [topInset] is the band at the viewport top that something else covers
  /// (the landing inset: a category strip over the body), so a span is "in
  /// view" only below it. A span already in view keeps [pixels]; one taller
  /// than the room left shows its top. The result is not clamped to the
  /// scroll range.
  @internal
  static double scrollOffsetToReveal({
    required double top,
    required double bottom,
    required double pixels,
    required double viewportHeight,
    double topInset = 0,
  }) {
    if (top - pixels < topInset) return top - topInset;
    if (bottom > pixels + viewportHeight) {
      return math.min(bottom - viewportHeight, top - topInset);
    }
    return pixels;
  }
}
