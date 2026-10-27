import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, TextAffinity, TextDirection, TextRange;

import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text.dart';
import 'package:meta/meta.dart';

/// A character position and the side of a wrap it belongs to.
typedef ChatEmojiCaret = ({int offset, TextAffinity affinity});

/// What the selection surface of an emoji-only body answers, as pure geometry
/// over the squares of the layout and the rendered text of [text].
///
/// The surface contract (`MarkdownSelectionSurface`) is written for text: a
/// point becomes a character position, a position a caret, a range boxes.
/// Here every item is one atomic run of characters in one square, so each
/// answer is an item edge: nothing returned lies inside an item, which is
/// also why the selection never needs the markdown engine's atomic ranges.
@internal
final class ChatEmojiTextLayout {
  /// Creates the layout of [text] whose item squares are [items].
  ChatEmojiTextLayout({required this.text, required this.items, required this.direction})
    : assert(items.length == text.itemRanges.length, 'One square per item.'),
      _rows = _rowsOf(items);

  /// The characters of the items.
  final ChatEmojiText text;

  /// The square of each item, in the order of the message.
  final List<Rect> items;

  /// The direction the lines start from.
  final TextDirection direction;

  /// The items of each line, in reading order, top to bottom.
  final List<List<int>> _rows;

  static List<List<int>> _rowsOf(List<Rect> items) {
    final rows = <List<int>>[];
    double? top;
    for (var i = 0; i < items.length; i++) {
      if (top == null || items[i].top != top) {
        rows.add(<int>[]);
        top = items[i].top;
      }
      rows.last.add(i);
    }
    return rows;
  }

  bool get _ltr => direction == TextDirection.ltr;

  // The x of the side an item starts from, and of the side it ends at.
  double _leading(Rect rect) => _ltr ? rect.left : rect.right;
  double _trailing(Rect rect) => _ltr ? rect.right : rect.left;

  /// The line nearest to [y]: its own when [y] is inside it, else the nearest
  /// by distance (a blank line between two belongs to the nearer).
  List<int>? _rowAt(double y) {
    List<int>? best;
    var bestDistance = double.infinity;
    for (final row in _rows) {
      final rect = items[row.first];
      final distance = y < rect.top
          ? rect.top - y
          : y > rect.bottom
          ? y - rect.bottom
          : 0.0;
      if (distance < bestDistance) {
        best = row;
        bestDistance = distance;
      }
    }
    return best;
  }

  // Distance from [x] to the span of [rect] along the line.
  double _gap(Rect rect, double x) => x < rect.left
      ? rect.left - x
      : x > rect.right
      ? x - rect.right
      : 0.0;

  /// The item of the line nearest to [y] that is nearest to [local]'s x, or
  /// null when there are no items.
  int? itemAt(Offset local) {
    final row = _rowAt(local.dy);
    if (row == null) return null;
    int? best;
    var bestDistance = double.infinity;
    for (final i in row) {
      final distance = _gap(items[i], local.dx);
      // Strictly nearer, so a point exactly between two goes to the earlier.
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Whether [local] is inside the square of an item: the glyph ink, not the
  /// gap between two items or the empty end of a line.
  bool hitsItem(Offset local) => items.any((rect) => rect.contains(local));

  /// The character position nearest to [local], or null with no items.
  ///
  /// The half of the square a point is in, counted from the side the line
  /// starts from, says whether it is the item's start (downstream, the start
  /// of that line) or its end (upstream, the end of that line). A point
  /// before or after the line is clamped to its first start and last end.
  ChatEmojiCaret? hitAt(Offset local) {
    final row = _rowAt(local.dy);
    final i = itemAt(local);
    if (row == null || i == null) return null;
    final range = text.itemRanges[i];
    final rect = items[i];
    final firstLeading = _leading(items[row.first]);
    final lastTrailing = _trailing(items[row.last]);
    final before = _ltr ? local.dx <= firstLeading : local.dx >= firstLeading;
    final after = _ltr ? local.dx >= lastTrailing : local.dx <= lastTrailing;
    if (before && i == row.first) {
      return (offset: range.start, affinity: TextAffinity.downstream);
    }
    if (after && i == row.last) {
      return (offset: range.end, affinity: TextAffinity.upstream);
    }
    final leadingHalf = _ltr ? local.dx < rect.center.dx : local.dx > rect.center.dx;
    return leadingHalf
        ? (offset: range.start, affinity: TextAffinity.downstream)
        : (offset: range.end, affinity: TextAffinity.upstream);
  }

  /// The zero-width rectangle of the caret at [offset], on the side of a wrap
  /// [affinity] says, in the body's coordinates; null with no items.
  ///
  /// An offset inside a run of line breaks is the start of the item after it;
  /// one inside an item is that item's edge on [affinity]'s side; one before
  /// the first item or after the last is that item's edge.
  Rect? caretRect(int offset, TextAffinity affinity) {
    final ranges = text.itemRanges;
    if (ranges.isEmpty) return null;
    int? starting;
    int? ending;
    for (var i = 0; i < ranges.length; i++) {
      if (ranges[i].start == offset) starting ??= i;
      if (ranges[i].end == offset) ending = i;
    }
    Rect edge(Rect rect, double x) => Rect.fromLTWH(x, rect.top, 0, rect.height);
    Rect leadingOf(int i) => edge(items[i], _leading(items[i]));
    Rect trailingOf(int i) => edge(items[i], _trailing(items[i]));
    if (starting != null && ending != null) {
      return affinity == TextAffinity.upstream ? trailingOf(ending) : leadingOf(starting);
    }
    if (starting != null) return leadingOf(starting);
    if (ending != null) return trailingOf(ending);
    if (offset <= ranges.first.start) return leadingOf(0);
    if (offset >= ranges.last.end) return trailingOf(ranges.length - 1);
    // Inside an item (between the code units of one emoji): its edge on the
    // side [affinity] says.
    final inside = ranges.indexWhere((range) => range.start < offset && offset < range.end);
    if (inside >= 0) {
      return affinity == TextAffinity.upstream ? trailingOf(inside) : leadingOf(inside);
    }
    // Inside a run of breaks: where the next item starts.
    final next = ranges.indexWhere((range) => range.start > offset);
    return leadingOf(next);
  }

  /// The word at [local]: the characters of the item nearest to it. An emoji
  /// is a word of its own, as the reference client's emoji spans are.
  TextRange? wordAt(Offset local) {
    final i = itemAt(local);
    return i == null ? null : text.itemRanges[i];
  }

  Iterable<int> _itemsIn(int start, int end) sync* {
    if (start >= end) return;
    final ranges = text.itemRanges;
    for (var i = 0; i < ranges.length; i++) {
      if (math.min(end, ranges[i].end) > math.max(start, ranges[i].start)) {
        yield i;
      }
    }
  }

  /// The square of each item the characters `[start, end)` reach, in reading
  /// order: the per-item boxes, for a style that wants them apart.
  List<Rect> boxesForRange(int start, int end) => [for (final i in _itemsIn(start, end)) items[i]];

  /// One box per line, joining the squares of the selected items on it: the
  /// shape of a text selection, a line tall and without a gap between items.
  List<Rect> lineBoxesForRange(int start, int end) {
    final lines = <Rect>[];
    double? top;
    for (final i in _itemsIn(start, end)) {
      final rect = items[i];
      if (top != null && rect.top == top) {
        lines.last = lines.last.expandToInclude(rect);
      } else {
        lines.add(rect);
        top = rect.top;
      }
    }
    return lines;
  }
}
