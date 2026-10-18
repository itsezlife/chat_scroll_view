import 'dart:ui';

/// The selection highlight as one shape, with the lines joined.
///
/// [boxes] are the engine's selection boxes in the editable's coordinates, one
/// or more per line. Two things make a translucent highlight read as a stack
/// of ribbons when each box is drawn on its own:
///
/// - The engine rounds every line's height, so a line's boxes can end a fraction
///   of a pixel short of the next line's top, whichever `BoxHeightStyle` is
///   asked for. That is a gap in the shape.
/// - Boxes that share an edge rarely share it on a device pixel. Each covers
///   part of the edge pixel and the two partial coverages composite to less
///   than the colour paints anywhere else, a seam even where the boxes meet
///   exactly.
///
/// The gap is closed by a bridge between each box and the box below it that
/// starts less than [maxLineGap] under it, over the width the two share, so a
/// line that stops short of the one above it keeps its step. A break wider than
/// [maxLineGap] is one the caller means to keep. The seam is removed by
/// returning one [Path]: a path is filled as one coverage, so the edges its
/// parts share and the areas they overlap are painted once.
///
/// The shape stops at [clip], the editable's own box.
Path selectionHighlightPath(
  Iterable<Rect> boxes, {
  required double maxLineGap,
  required Rect clip,
}) {
  final byTop = boxes.toList()..sort((a, b) => a.top.compareTo(b.top));
  final shape = Path();
  void add(Rect rect) {
    final visible = rect.intersect(clip);
    if (!visible.isEmpty) {
      shape.addRect(visible);
    }
  }

  for (var i = 0; i < byTop.length; i++) {
    final above = byTop[i];
    add(above);
    for (var j = i + 1; j < byTop.length; j++) {
      final below = byTop[j];
      final gap = below.top - above.bottom;
      if (gap > maxLineGap) {
        // Sorted by top: nothing after this one is closer.
        break;
      }
      final left = above.left > below.left ? above.left : below.left;
      final right = above.right < below.right ? above.right : below.right;
      if (gap > 0 && left < right) {
        add(Rect.fromLTRB(left, above.bottom, right, below.top));
      }
    }
  }
  return shape;
}
