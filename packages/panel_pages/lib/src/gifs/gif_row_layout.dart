import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:meta/meta.dart';

/// One clip's place in a [GifRow]: its index in the list laid out, where it
/// starts along the row and how wide it is.
@immutable
final class GifCell {
  /// A cell for the clip [index], starting [left] from the start edge.
  const GifCell({required this.index, required this.left, required this.width});

  /// The clip's index in the list given to [GifRowLayout.of].
  final int index;

  /// Distance from the start edge of the row to the cell's, in logical pixels.
  final double left;

  /// Width of the cell, less the [GifRowLayout.gap] that follows it unless it
  /// ends the row.
  final double width;

  @override
  bool operator ==(Object other) =>
      other is GifCell &&
      other.index == index &&
      other.left == left &&
      other.width == width;

  @override
  int get hashCode => Object.hash(index, left, width);

  @override
  String toString() => 'GifCell($index, $left, $width)';
}

/// One row of justified clips: its cells, which fill the width.
@immutable
final class GifRow {
  /// A row of [cells].
  const GifRow(this.cells);

  /// The cells, from the start edge.
  final List<GifCell> cells;

  /// The height a row takes: [GifRowLayout.rowExtent] under the
  /// [GifRowLayout.gap] above it.
  double get height => GifRowLayout.gap + GifRowLayout.rowExtent;
}

/// A justified grid of GIFs: clips of any proportion in
/// rows of one height that fill the width.
///
/// A port of `ExtendedGridLayoutManager.prepareLayout` as `GifLayoutManager`
/// uses it: the width is [spanCount] spans; a clip wants the spans its
/// proportions take at a row [rowExtent] tall (`floor(100 * w / h * 100 /
/// width)`, at most the whole row); it joins the row while the spans left hold
/// it, or nearly (a wide clip, over 33 spans, may take up to 15 fewer than it
/// wants); otherwise the row is closed and the spans it has left are shared
/// out between its clips, the last taking the remainder. The last row is
/// closed the same way, so it fills the width too.
///
/// The decoration of `GifSearchAdapter`'s grid puts [gap] above every row and
/// [gap] after every cell but the last of its row.
///
/// A clip of a proportion beyond 4:1 or below 1:5 is laid out as the square of
/// its longer side, and a side of 0 counts as 100, as `fixSize` does.
abstract final class GifRowLayout {
  /// The spans a row is divided in: `new GifLayoutManager` passes 100.
  static const int spanCount = 100;

  /// The height a row is laid out for: 100, which is also the height a cell
  /// takes with no height given.
  static const double rowExtent = 100;

  /// The gap above a row and after a cell.
  static const double gap = 2;

  /// The rows the clips of [sizes] make in a row [width] wide.
  static List<GifRow> of(List<Size> sizes, {required double width}) {
    if (sizes.isEmpty) return const [];
    // An unmeasured view is laid out as 100 wide.
    final available = width <= 0 ? 100.0 : width;
    final spans = List<int>.filled(sizes.length, 0);
    final rowOf = <List<int>>[];
    var row = <int>[];
    var spanLeft = spanCount;

    // Closes the current row: its leftover spans are shared out between its
    // clips, the last taking what is then left.
    void closeRow() {
      if (row.isEmpty) return;
      if (spanLeft != 0) {
        final perItem = spanLeft ~/ row.length;
        for (final (i, index) in row.indexed) {
          if (i == row.length - 1) {
            spans[index] += spanLeft;
          } else {
            spans[index] += perItem;
          }
          spanLeft -= perItem;
        }
      }
      rowOf.add(row);
      row = <int>[];
      spanLeft = spanCount;
    }

    for (final (index, raw) in sizes.indexed) {
      final size = _fixed(raw);
      final required = math.min(
        spanCount,
        (spanCount * (size.width / size.height * rowExtent / available))
            .floor(),
      );
      final closes =
          spanLeft < required || (required > 33 && spanLeft < required - 15);
      if (closes) closeRow();
      row.add(index);
      spanLeft -= required;
      spans[index] = required;
    }
    closeRow();

    return [
      for (final members in rowOf) GifRow(_cells(members, spans, available)),
    ];
  }

  static List<GifCell> _cells(
    List<int> members,
    List<int> spans,
    double width,
  ) {
    final cells = <GifCell>[];
    var spansBefore = 0;
    for (final (i, index) in members.indexed) {
      final left = width * spansBefore / spanCount;
      final end = width * (spansBefore + spans[index]) / spanCount;
      final last = i == members.length - 1;
      cells.add(
        GifCell(index: index, left: left, width: end - left - (last ? 0 : gap)),
      );
      spansBefore += spans[index];
    }
    return cells;
  }

  // `fixSize`: a side of 0 is 100; beyond 4:1 or below 1:5 the clip is the
  // square of its longer side.
  static Size _fixed(Size size) {
    final width = size.width == 0 ? 100.0 : size.width;
    final height = size.height == 0 ? 100.0 : size.height;
    final aspect = width / height;
    if (aspect > 4.0 || aspect < 0.2) {
      final side = math.max(width, height);
      return Size(side, side);
    }
    return Size(width, height);
  }
}
