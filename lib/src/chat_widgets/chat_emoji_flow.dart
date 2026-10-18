import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size, TextDirection;

import 'package:meta/meta.dart';

/// Where the items of an emoji-only text sit: squares of one side set in
/// lines that start at the reading direction's edge and wrap at a width, with
/// the message's own line breaks.
///
/// Pure geometry, so the sizes and the wrap are testable without a render
/// tree. It is what the reference client's layout of a text made of equal boxes comes to
/// (each emoji span reserves one square, and the line is as tall as the
/// square).
@immutable
final class ChatEmojiFlow {
  const ChatEmojiFlow._(this.size, this.rects);

  /// Lays out one square of side [box] per entry of [lineBreaksBefore], the
  /// number of line breaks before that item, surrounded by [inset].
  ///
  /// A line takes items until the next would pass [maxWidth], and never fewer
  /// than one. A break moves to the next line, and a second leaves a blank
  /// line the height of a square. [maxWidth] may be infinite. The result
  /// shrinks to the widest line; for [TextDirection.rtl] every line starts at
  /// the right edge.
  factory ChatEmojiFlow.of({
    required List<int> lineBreaksBefore,
    required double box,
    required double maxWidth,
    required TextDirection direction,
    double inset = 0,
  }) {
    final cells = <(int line, int column)>[];
    var line = 0;
    var column = 0;
    var widest = 0;
    for (var i = 0; i < lineBreaksBefore.length; i++) {
      final breaks = lineBreaksBefore[i];
      if (i > 0 && breaks > 0) {
        line += breaks;
        column = 0;
      } else if (column > 0 && (column + 1) * box > maxWidth + _slack) {
        line++;
        column = 0;
      }
      cells.add((line, column));
      column++;
      widest = math.max(widest, column);
    }
    final width = widest * box;
    final height = cells.isEmpty ? 0.0 : (line + 1) * box;
    final rects = [
      for (final (line, column) in cells)
        Rect.fromLTWH(
          inset +
              switch (direction) {
                TextDirection.ltr => column * box,
                TextDirection.rtl => width - (column + 1) * box,
              },
          inset + line * box,
          box,
          box,
        ),
    ];
    return ChatEmojiFlow._(
      Size(width + 2 * inset, height + 2 * inset),
      List.unmodifiable(rects),
    );
  }

  // Float noise in `n × box` must not wrap an item that fills the line.
  static const double _slack = 1e-9;

  /// The size the items take, with the inset.
  final Size size;

  /// The square of each item, in the order given.
  final List<Rect> rects;

  /// The index of the item whose square holds [point], or null.
  int? itemAt(Offset point) {
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(point)) return i;
    }
    return null;
  }
}
