import 'dart:math' as math;

import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/media_layout_metrics.dart';
import 'package:meta/meta.dart';

/// One media item's cell in a projected mosaic: its pixel rect.
///
/// Owns: the [rect] derived from a [GroupedMessagePosition], addressed by
/// [itemId]. Does not own: corner radii (the layout's `MediaCornerPolicy`
/// resolves them from the cell's neighbours), fills or the picture.
@immutable
final class MosaicCellLayout {
  /// Creates a projected cell (normally from [MosaicLayout.project]).
  const MosaicCellLayout({required this.rect, required this.position});

  /// Cell bounds in mosaic-local coordinates (origin at the mosaic's top
  /// left).
  final Rect rect;

  /// The abstract position the cell was projected from.
  final GroupedMessagePosition position;

  /// The media item this cell draws.
  MediaItemId get itemId => position.itemId;
}

/// Pixel projection of [GroupedMessagePosition]s into a fixed mosaic width:
/// the mosaic block of a media layout.
///
/// Owns: the mosaic [size] and its [cells] with their seams, each addressed
/// by its media item ([cellOf]). Does not own: the mosaic algorithm
/// ([GroupedMessages.calculate]), corner radii or the pictures.
///
/// ## Coordinate mapping
///
/// - **Horizontal:** [GroupedMessagePosition.leftSpanOffset] when set;
///   otherwise the furthest right edge of the overlapping cells to the
///   left. The width is `pw / maxSizeWidth * mosaicWidth`.
/// - **Vertical:** row bands come from one-row cells' `ph` (and from
///   multi-row cells without siblings, split evenly).
///   [GroupedMessagePosition.siblingHeights] is not in row order: its
///   fractions are only summed for the tall cell, and row tops still come
///   from the peer cells on each row.
/// - **Seams:** `cellGap` insets every shared edge by half on each side.
///
/// Empty `positions` or a non-positive `mosaicWidth` give [Size.zero] and no
/// cells.
final class MosaicLayout {
  MosaicLayout._({required this.size, required this.cells})
    : _cellsById = {for (final cell in cells) cell.itemId: cell};

  /// Projects [positions] into pixel rects at [mosaicWidth].
  ///
  /// [maxSizeWidth] / [maxSizeHeight] MUST match the calculate pass that
  /// produced [positions] (defaults match [MediaLayoutMetrics]).
  ///
  /// [rowHeightUnit] is the pixel height a position's `ph` of 1 maps to.
  /// Null keeps the mosaic's own proportions: [maxSizeHeight] scaled with
  /// the width. A policy that bounds album height by the screen passes its
  /// max height here.
  factory MosaicLayout.project({
    required List<GroupedMessagePosition> positions,
    required double mosaicWidth,
    double cellGap = MediaLayoutMetrics.cellGap,
    double maxSizeWidth = MediaLayoutMetrics.groupedMaxSizeWidth,
    double maxSizeHeight = MediaLayoutMetrics.groupedMaxSizeHeight,
    double? rowHeightUnit,
  }) {
    if (positions.isEmpty || mosaicWidth <= 0) {
      return MosaicLayout._(size: Size.zero, cells: const []);
    }

    final sx = mosaicWidth / maxSizeWidth;
    final heightUnit = rowHeightUnit ?? maxSizeHeight * sx;

    var maxRow = 0;
    for (final p in positions) {
      maxRow = math.max(maxRow, p.maxY);
    }

    // Row bands from peers only: siblingHeights is not in row order (a
    // narrow-first layout stores [bottom, top]), so it is only ever summed.
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

    final lefts = Map<GroupedMessagePosition, int>.identity();
    final cells = <MosaicCellLayout>[
      for (final pos in positions)
        _cellFor(
          pos: pos,
          left: _leftFor(pos, positions, lefts) * sx,
          sx: sx,
          rowTops: rowTops,
          rowHeights: rowHeights,
          cellGap: cellGap,
        ),
    ];

    return MosaicLayout._(size: Size(mosaicWidth, mosaicHeight), cells: cells);
  }

  /// Outer mosaic size; the seams sit inside this box.
  final Size size;

  /// Cells in the order of the input positions.
  final List<MosaicCellLayout> cells;

  final Map<MediaItemId, MosaicCellLayout> _cellsById;

  /// The cell of the media item [id], or null when it is not in the mosaic.
  MosaicCellLayout? cellOf(MediaItemId id) => _cellsById[id];

  /// Pixel left edge: [leftSpanOffset] when set, else the furthest right
  /// edge of the overlapping cells left of [pos] (smaller
  /// [GroupedMessagePosition.maxX]).
  ///
  /// A neighbour's right edge is its own left edge plus its width, found the
  /// same way: a line of three places its third cell after the first two,
  /// not after the wider of them. [lefts] memoises the span-unit lefts.
  static int _leftFor(
    GroupedMessagePosition pos,
    List<GroupedMessagePosition> positions,
    Map<GroupedMessagePosition, int> lefts,
  ) {
    if (lefts[pos] case final left?) {
      return left;
    }
    if (pos.leftSpanOffset != 0) {
      return lefts[pos] = pos.leftSpanOffset;
    }
    var left = 0;
    for (final other in positions) {
      if (identical(other, pos)) {
        continue;
      }
      final yOverlap = other.maxY >= pos.minY && other.minY <= pos.maxY;
      if (yOverlap && other.maxX < pos.minX) {
        left = math.max(left, _leftFor(other, positions, lefts) + other.pw);
      }
    }
    return lefts[pos] = left;
  }

  /// Builds one [MosaicCellLayout] from row bands, then insets shared edges
  /// by `cellGap / 2`.
  ///
  /// Spanning cells (including sibling stacks) use the sum of covered
  /// [rowHeights] so their bottom aligns with the peer column.
  static MosaicCellLayout _cellFor({
    required GroupedMessagePosition pos,
    required double left,
    required double sx,
    required List<double> rowTops,
    required List<double> rowHeights,
    required double cellGap,
  }) {
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

    return MosaicCellLayout(rect: Rect.fromLTRB(l, t, r, b), position: pos);
  }
}
