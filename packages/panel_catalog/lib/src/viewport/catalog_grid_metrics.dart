import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';
import 'package:panel_catalog/src/model/section_layout.dart';

/// One section's grid, resolved against the viewport defaults at one width.
///
/// The single place a [SectionLayout] meets the viewport defaults, the padding
/// and the constraint width, so slot projection, section landing and the
/// glyph-box rule cannot disagree about a section's cell.
final class CatalogGridMetrics {
  /// Creates resolved metrics. Use [resolveCatalogGrid].
  const CatalogGridMetrics({
    required this.spanCount,
    required this.cellWidth,
    required this.cellHeight,
    required this.headerExtent,
    required this.insets,
    required this.left,
    required this.usableWidth,
  });

  /// Columns.
  final int spanCount;

  /// Cell width in content coordinates.
  final double cellWidth;

  /// Cell height, which is the row pitch.
  final double cellHeight;

  /// Header band height.
  final double headerExtent;

  /// The section's own insets (inside the viewport padding).
  final EdgeInsets insets;

  /// Content x of the first column's left edge: viewport padding plus the
  /// section's left inset.
  final double left;

  /// Width the section's columns and header share.
  final double usableWidth;

  /// Number of rows that [leafCount] leaves take at [spanCount] columns.
  int rowCountFor(int leafCount) =>
      leafCount == 0 ? 0 : (leafCount + spanCount - 1) ~/ spanCount;

  /// The side of the glyph box a cell of this grid draws in.
  double get glyphBoxExtent => catalogGlyphBoxExtent(cellWidth, cellHeight);
}

/// Resolves [layout] (null = all defaults) against the viewport defaults.
///
/// A width with nothing left to divide (a degenerate constraint) makes the
/// cells square at the cell extent rather than zero wide.
CatalogGridMetrics resolveCatalogGrid(
  SectionLayout? layout, {
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  required double maxWidth,
}) {
  final grid = switch (layout) {
    final SectionLayout$Grid grid => grid,
    null => const SectionLayout$Grid(),
  };
  final span = grid.spanCount ?? spanCount;
  final insets = grid.insets;
  final usableWidth = math.max(
    0.0,
    maxWidth - padding.horizontal - insets.horizontal,
  );
  final fixedHeight = grid.cellExtent ?? cellExtent;
  final cellWidth = usableWidth > 0 ? usableWidth / span : fixedHeight;
  final aspect = grid.cellAspect;
  return CatalogGridMetrics(
    spanCount: span,
    cellWidth: cellWidth,
    cellHeight: aspect != null && usableWidth > 0
        ? cellWidth / aspect
        : fixedHeight,
    headerExtent: grid.headerExtent ?? headerExtent,
    insets: insets,
    left: padding.left + insets.left,
    usableWidth: usableWidth,
  );
}

/// The largest glyph box any of [layouts] draws a glyph in, for a viewport of
/// [maxWidth] with these defaults and [padding].
///
/// A host that bakes glyphs has **one** baked size per atlas, so it sizes it
/// for the largest box and every section draws the same sprites scaled down:
/// sizing for a smaller one would blur the sections with larger cells, and a
/// second atlas for them would double the resident pages. Pass the layout of
/// each section the atlas serves (`null` is the viewport default); with none,
/// the default's box is returned. The box is [catalogGlyphBoxExtent] of the
/// resolved cell, the very formula the painter draws with.
double largestCatalogGlyphBox({
  required Iterable<SectionLayout?> layouts,
  required int spanCount,
  required double cellExtent,
  required EdgeInsets padding,
  required double maxWidth,
}) {
  double boxOf(SectionLayout? layout) => resolveCatalogGrid(
    layout,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: 0,
    padding: padding,
    maxWidth: maxWidth,
  ).glyphBoxExtent;

  var largest = 0.0;
  var any = false;
  for (final layout in layouts) {
    any = true;
    largest = math.max(largest, boxOf(layout));
  }
  return any ? largest : boxOf(null);
}
