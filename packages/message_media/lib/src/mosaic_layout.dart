import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/media_layout_metrics.dart';

/// One cell’s pixel rect and corner radii inside a projected mosaic.
///
/// Owns: paint-ready [rect] and [borderRadius] derived from a
/// [GroupedMessagePosition]. Does not own: fill color or image bind.
final class MosaicCellLayout {
  /// Creates a projected cell (normally from [MosaicLayout.project]).
  const MosaicCellLayout({
    required this.rect,
    required this.borderRadius,
    required this.position,
  });

  /// Cell bounds in mosaic-local coordinates (origin top-left of the mosaic).
  final Rect rect;

  /// Outer corners use [MediaLayoutMetrics.mediaOuterRadius] when the matching
  /// edge flag is present; otherwise [MediaLayoutMetrics.mediaInnerRadius].
  final BorderRadius borderRadius;

  /// Source geometry from [GroupedMessages.calculate] (same list order).
  final GroupedMessagePosition position;
}

/// Pixel projection of [GroupedMessagePosition]s into a fixed mosaic width.
///
/// Owns: mosaic [size] and ordered [cells] with gaps and radii. Does not own:
/// calculate math, chat fan-out / group rows, or network images.
///
/// ## Coordinate mapping
///
/// - **Horizontal:** prefer [GroupedMessagePosition.leftSpanOffset]; otherwise
///   the max right edge of overlapping cells with smaller `maxX`. Width is
///   `pw / maxSizeWidth * mosaicWidth`.
/// - **Vertical:** row bands come from single-row cells’ `ph` (and evenly
///   split multi-row cells that lack siblings). [GroupedMessagePosition.siblingHeights]
///   is **not** row-ordered — Java stores unordered fractions to **sum** for
///   the tall cell; row tops still come from the peer cells on each row.
/// - **Gaps:** [cellGap] insets shared edges by half on each side.
///
/// Empty [positions] or non-positive [mosaicWidth] → [Size.zero] and no cells.
final class MosaicLayout {
  MosaicLayout._({required this.size, required this.cells});

  /// Outer mosaic size; cell gaps sit **inside** this box.
  final Size size;

  /// Cells in the same order as the input positions.
  final List<MosaicCellLayout> cells;

  /// Projects [positions] into pixel rects at [mosaicWidth].
  ///
  /// [bubbleRadius] drives outer corners via
  /// [MediaLayoutMetrics.mediaOuterRadius]. [maxSizeWidth] / [maxSizeHeight]
  /// MUST match the calculate pass that produced [positions] (defaults match
  /// [MediaLayoutMetrics]).
  factory MosaicLayout.project({
    required List<GroupedMessagePosition> positions,
    required double mosaicWidth,
    double cellGap = MediaLayoutMetrics.cellGap,
    double bubbleRadius = 17,
    double maxSizeWidth = MediaLayoutMetrics.groupedMaxSizeWidth,
    double maxSizeHeight = MediaLayoutMetrics.groupedMaxSizeHeight,
  }) {
    if (positions.isEmpty || mosaicWidth <= 0) {
      return MosaicLayout._(size: Size.zero, cells: const []);
    }

    final sx = mosaicWidth / maxSizeWidth;
    final heightUnit = maxSizeHeight * sx;
    final outerR = MediaLayoutMetrics.mediaOuterRadius(
      bubbleRadius: bubbleRadius,
    );
    const innerR = MediaLayoutMetrics.mediaInnerRadius;

    var maxRow = 0;
    for (final p in positions) {
      maxRow = math.max(maxRow, p.maxY);
    }

    // Row bands from peers only — never index siblingHeights as top→bottom
    // (Java stores e.g. [bottom, top] for sum-only).
    final rowHeights = List<double>.filled(maxRow + 1, 0);
    for (final pos in positions) {
      if (pos.siblingHeights != null) {
        continue;
      }
      if (pos.minY == pos.maxY) {
        rowHeights[pos.minY] = math.max(
          rowHeights[pos.minY],
          pos.ph * heightUnit,
        );
      } else {
        final span = pos.maxY - pos.minY + 1;
        final each = pos.ph * heightUnit / span;
        for (var y = pos.minY; y <= pos.maxY; y++) {
          rowHeights[y] = math.max(rowHeights[y], each);
        }
      }
    }

    // If a sibling stack left any row empty, fall back to summing that cell’s
    // siblingHeights across its span (equal total; equal split only as last
    // resort when peers are missing).
    for (final pos in positions) {
      if (pos.siblingHeights case final siblings?) {
        var covered = 0.0;
        for (var y = pos.minY; y <= pos.maxY; y++) {
          covered += rowHeights[y];
        }
        if (covered > 0) {
          continue;
        }
        var sum = 0.0;
        for (final s in siblings) {
          sum += s * heightUnit;
        }
        final span = pos.maxY - pos.minY + 1;
        final each = sum / span;
        for (var y = pos.minY; y <= pos.maxY; y++) {
          rowHeights[y] = each;
        }
      }
    }

    final rowTops = List<double>.filled(maxRow + 1, 0);
    for (var y = 1; y <= maxRow; y++) {
      rowTops[y] = rowTops[y - 1] + rowHeights[y - 1];
    }
    final mosaicHeight = rowTops[maxRow] + rowHeights[maxRow];

    final cells = <MosaicCellLayout>[
      for (final pos in positions)
        _cellFor(
          pos: pos,
          positions: positions,
          sx: sx,
          rowTops: rowTops,
          rowHeights: rowHeights,
          cellGap: cellGap,
          outerR: outerR,
          innerR: innerR,
        ),
    ];

    return MosaicLayout._(size: Size(mosaicWidth, mosaicHeight), cells: cells);
  }

  /// Pixel left edge: [leftSpanOffset] when set, else max right edge of
  /// overlapping cells with smaller [GroupedMessagePosition.maxX].
  static double _leftFor(
    GroupedMessagePosition pos,
    List<GroupedMessagePosition> positions,
    double sx,
  ) {
    if (pos.leftSpanOffset != 0) {
      return pos.leftSpanOffset * sx;
    }
    var left = 0.0;
    for (final other in positions) {
      if (identical(other, pos)) {
        continue;
      }
      final yOverlap = other.maxY >= pos.minY && other.minY <= pos.maxY;
      if (yOverlap && other.maxX < pos.minX) {
        left = math.max(left, (other.leftSpanOffset + other.pw) * sx);
      }
    }
    return left;
  }

  /// Builds one [MosaicCellLayout] from row bands, then insets shared edges
  /// by `cellGap / 2` and assigns outer/inner radii from edge flags.
  ///
  /// Spanning cells (including sibling stacks) use the sum of covered
  /// [rowHeights] so their bottom aligns with the peer column.
  static MosaicCellLayout _cellFor({
    required GroupedMessagePosition pos,
    required List<GroupedMessagePosition> positions,
    required double sx,
    required List<double> rowTops,
    required List<double> rowHeights,
    required double cellGap,
    required double outerR,
    required double innerR,
  }) {
    final left = _leftFor(pos, positions, sx);
    final width = pos.pw * sx;
    final top = rowTops[pos.minY];
    var height = 0.0;
    for (var y = pos.minY; y <= pos.maxY; y++) {
      height += rowHeights[y];
    }

    var l = left;
    var t = top;
    var r = left + width;
    var b = top + height;
    final half = cellGap / 2;
    if (!pos.hasLeft) {
      l += half;
    }
    if (!pos.hasRight) {
      r -= half;
    }
    if (!pos.hasTop) {
      t += half;
    }
    if (!pos.hasBottom) {
      b -= half;
    }

    return MosaicCellLayout(
      rect: Rect.fromLTRB(l, t, r, b),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(pos.hasTop && pos.hasLeft ? outerR : innerR),
        topRight: Radius.circular(pos.hasTop && pos.hasRight ? outerR : innerR),
        bottomLeft: Radius.circular(
          pos.hasBottom && pos.hasLeft ? outerR : innerR,
        ),
        bottomRight: Radius.circular(
          pos.hasBottom && pos.hasRight ? outerR : innerR,
        ),
      ),
      position: pos,
    );
  }
}
