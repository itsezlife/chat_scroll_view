import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/policy/mosaic_algorithm.dart';
import 'package:meta/meta.dart';

/// The desktop family's mosaic: the album laid out once at [maxWidth] in
/// whole pixels, then scaled down to the width the block may take.
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [maxWidth] | 430 | The width the album is laid out at, and its widest |
/// | [minWidth] | 100 | The narrowest box a line aims for |
/// | [spacing] | 4 | Seam between boxes at [maxWidth], scaled with the album |
///
/// ## The layout
///
/// Each item's aspect ratio (width / height; an item without dimensions is
/// a square) is classed wide (over 1.2), narrow (under 0.8) or square.
///
/// - Two to four items, none wider than 2, take a fixed form inside a
///   [maxWidth] square: two items side by side (equal halves when both are
///   wide or both square, else split by their ratios) or, both wide and
///   alike and wider on average than 1.4, stacked; three items as one
///   narrow item left of two stacked, else one item over two; four items
///   as one wide item over three, else one item left of three stacked.
/// - Five or more items, or any item wider than 2, go in lines. Each ratio
///   is clamped to 1–2.75 when the album is wide on average (over 1.1),
///   else to 2/3–1. Every split into two to four lines of at most three
///   items (four in a middle line of a narrow album) is tried, and the one
///   whose height is nearest to 4/3 of [maxWidth] wins; a line under
///   [minWidth] high, or a line with fewer items than the one above it,
///   counts half as far again.
///
/// ## Scaling
///
/// A narrower block scales every box edge by `width / maxWidth`, rounded to
/// whole pixels, so seams stay aligned between lines. The album is never
/// scaled up.
@immutable
final class DesktopMosaicAlgorithm implements MosaicAlgorithm {
  /// The desktop mosaic; any value can be replaced.
  const DesktopMosaicAlgorithm({
    this.maxWidth = 430,
    this.minWidth = 100,
    this.spacing = 4,
  });

  /// See the class table.
  final int maxWidth;

  /// See the class table.
  final int minWidth;

  /// See the class table.
  final int spacing;

  @override
  String get name => 'desktop';

  @override
  MosaicArrangement arrange({
    required List<MediaItem> items,
    required double width,
    required MediaLayoutInput input,
  }) {
    final ratios = [
      for (final item in items)
        switch (item.descriptor.size) {
          ContentSize(width: final w, height: final h) when w > 0 && h > 0 =>
            w / h,
          _ => 1.0,
        },
    ];
    final boxes = _Layouter(
      ratios: ratios,
      maxWidth: maxWidth,
      minWidth: minWidth,
      spacing: spacing,
    ).layout();
    final laidOutWidth = boxes.fold(0, (w, box) => math.max(w, box.right));
    final targetWidth = math.min(width, laidOutWidth.toDouble());
    final factor = targetWidth / laidOutWidth;
    double scale(int value) => (value * factor).roundToDouble();
    final gap = scale(spacing);
    var height = 0.0;
    final placements = <MosaicPlacement>[];
    for (final (index, box) in boxes.indexed) {
      // Each box's far edge is scaled together with the seam after it, so
      // two boxes that meet at one seam keep meeting after the rounding.
      final skipRight = !box.edges.hasRight;
      final skipBottom = !box.edges.hasBottom;
      final left = scale(box.left);
      final top = scale(box.top);
      final right = scale(box.right + (skipRight ? spacing : 0));
      final bottom = scale(box.bottom + (skipBottom ? spacing : 0));
      // An extreme ratio can leave a box no room; it keeps its cell, empty.
      final w = math.max<double>(0, right - left - (skipRight ? gap : 0));
      final h = math.max<double>(0, bottom - top - (skipBottom ? gap : 0));
      placements.add(
        MosaicPlacement(
          itemId: items[index].id,
          rect: Rect.fromLTWH(left, top, w, h),
          edges: box.edges,
        ),
      );
      height = math.max(height, top + h);
    }
    return MosaicArrangement(
      size: Size(targetWidth, height),
      placements: placements,
    );
  }

  /// A copy with the given values replaced.
  DesktopMosaicAlgorithm copyWith({
    int? maxWidth,
    int? minWidth,
    int? spacing,
  }) => DesktopMosaicAlgorithm(
    maxWidth: maxWidth ?? this.maxWidth,
    minWidth: minWidth ?? this.minWidth,
    spacing: spacing ?? this.spacing,
  );

  @override
  bool operator ==(Object other) =>
      other is DesktopMosaicAlgorithm &&
      other.maxWidth == maxWidth &&
      other.minWidth == minWidth &&
      other.spacing == spacing;

  @override
  int get hashCode => Object.hash(maxWidth, minWidth, spacing);
}

/// One box at the album's own width, in whole pixels.
final class _Box {
  const _Box(this.left, this.top, this.width, this.height, this.edges);

  final int left;
  final int top;
  final int width;
  final int height;
  final GroupedPositionFlags edges;

  int get right => left + width;
  int get bottom => top + height;
}

const _l = GroupedPositionFlags.left;
const _r = GroupedPositionFlags.right;
const _t = GroupedPositionFlags.top;
const _b = GroupedPositionFlags.bottom;

/// The album at its own width. Integer and rounded steps are kept as they
/// are: they decide where seams fall, and changing one moves a box by a
/// pixel against the family's other clients.
final class _Layouter {
  _Layouter({
    required this.ratios,
    required this.maxWidth,
    required this.minWidth,
    required this.spacing,
  }) : maxHeight = maxWidth,
       // The running sum starts at 1, not 0: the family's average is one
       // over the plain mean, and the forms below are tuned to it.
       averageRatio =
           ratios.fold<double>(1, (sum, r) => sum + r) / ratios.length,
       proportions = ratios
           .map((r) => r > 1.2 ? 'w' : (r < 0.8 ? 'n' : 'q'))
           .join();

  final List<double> ratios;
  final int maxWidth;
  final int maxHeight;
  final int minWidth;
  final int spacing;
  final double averageRatio;
  final String proportions;

  /// The square max box: width over height is 1.
  double get maxSizeRatio => maxWidth / maxHeight;

  List<_Box> layout() {
    final count = ratios.length;
    if (count >= 5 || ratios.any((r) => r > 2)) return _lines();
    return switch (count) {
      2 => _two(),
      3 => proportions[0] == 'n' ? _threeLeftAndOther() : _threeTopAndOther(),
      _ => proportions[0] == 'w' ? _fourTopAndOther() : _fourLeftAndOther(),
    };
  }

  List<_Box> _two() {
    if (proportions == 'ww' &&
        averageRatio > 1.4 * maxSizeRatio &&
        ratios[1] - ratios[0] < 0.2) {
      final height = math
          .min(
            maxWidth / ratios[0],
            math.min(maxWidth / ratios[1], (maxHeight - spacing) / 2),
          )
          .round();
      return [
        _Box(0, 0, maxWidth, height, _l | _t | _r),
        _Box(0, height + spacing, maxWidth, height, _l | _b | _r),
      ];
    }
    if (proportions == 'ww' || proportions == 'qq') {
      final width = (maxWidth - spacing) ~/ 2;
      final height = math
          .min(
            width / ratios[0],
            math.min(width / ratios[1], maxHeight.toDouble()),
          )
          .round();
      return [
        _Box(0, 0, width, height, _t | _l | _b),
        _Box(width + spacing, 0, width, height, _t | _r | _b),
      ];
    }
    final minimalWidth = (minWidth * 1.5).round();
    final secondWidth = math.min(
      math
          .max(
            0.4 * (maxWidth - spacing),
            (maxWidth - spacing) / ratios[0] / (1 / ratios[0] + 1 / ratios[1]),
          )
          .round(),
      maxWidth - spacing - minimalWidth,
    );
    final firstWidth = maxWidth - secondWidth - spacing;
    final height = math.min(
      maxHeight,
      math.min(firstWidth / ratios[0], secondWidth / ratios[1]).round(),
    );
    return [
      _Box(0, 0, firstWidth, height, _t | _l | _b),
      _Box(firstWidth + spacing, 0, secondWidth, height, _t | _r | _b),
    ];
  }

  List<_Box> _threeLeftAndOther() {
    final firstHeight = maxHeight;
    final thirdHeight = math
        .min(
          (maxHeight - spacing) / 2,
          ratios[1] * (maxWidth - spacing) / (ratios[2] + ratios[1]),
        )
        .round();
    final secondHeight = firstHeight - thirdHeight - spacing;
    final rightWidth = math.max(
      minWidth,
      math
          .min(
            (maxWidth - spacing) / 2,
            math.min(thirdHeight * ratios[2], secondHeight * ratios[1]),
          )
          .round(),
    );
    final leftWidth = math.min(
      (firstHeight * ratios[0]).round(),
      maxWidth - spacing - rightWidth,
    );
    final x = leftWidth + spacing;
    return [
      _Box(0, 0, leftWidth, firstHeight, _t | _l | _b),
      _Box(x, 0, rightWidth, secondHeight, _t | _r),
      _Box(x, secondHeight + spacing, rightWidth, thirdHeight, _b | _r),
    ];
  }

  List<_Box> _threeTopAndOther() {
    final firstWidth = maxWidth;
    final firstHeight = math
        .min(firstWidth / ratios[0], (maxHeight - spacing) * 0.66)
        .round();
    final secondWidth = (maxWidth - spacing) ~/ 2;
    final secondHeight = math.min(
      maxHeight - firstHeight - spacing,
      math.min(secondWidth / ratios[1], secondWidth / ratios[2]).round(),
    );
    final thirdWidth = firstWidth - secondWidth - spacing;
    final y = firstHeight + spacing;
    return [
      _Box(0, 0, firstWidth, firstHeight, _l | _t | _r),
      _Box(0, y, secondWidth, secondHeight, _b | _l),
      _Box(secondWidth + spacing, y, thirdWidth, secondHeight, _b | _r),
    ];
  }

  List<_Box> _fourTopAndOther() {
    final w = maxWidth;
    final h0 = math.min(w / ratios[0], (maxHeight - spacing) * 0.66).round();
    final h = ((maxWidth - 2 * spacing) / (ratios[1] + ratios[2] + ratios[3]))
        .round();
    final w0 = math.max(
      minWidth,
      math.min((maxWidth - 2 * spacing) * 0.4, h * ratios[1]).round(),
    );
    final w2 = math
        .max(
          math.max(minWidth.toDouble(), (maxWidth - 2 * spacing) * 0.33),
          h * ratios[3],
        )
        .round();
    final w1 = w - w0 - w2 - 2 * spacing;
    final h1 = math.min(maxHeight - h0 - spacing, h);
    final y = h0 + spacing;
    return [
      _Box(0, 0, w, h0, _l | _t | _r),
      _Box(0, y, w0, h1, _b | _l),
      _Box(w0 + spacing, y, w1, h1, _b),
      _Box(w0 + spacing + w1 + spacing, y, w2, h1, _r | _b),
    ];
  }

  List<_Box> _fourLeftAndOther() {
    final h = maxHeight;
    final w0 = math.min(h * ratios[0], (maxWidth - spacing) * 0.6).round();
    final w =
        ((maxHeight - 2 * spacing) /
                (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3]))
            .round();
    final h0 = (w / ratios[1]).round();
    final h1 = (w / ratios[2]).round();
    final h2 = h - h0 - h1 - 2 * spacing;
    final w1 = math.max(minWidth, math.min(maxWidth - w0 - spacing, w));
    final x = w0 + spacing;
    return [
      _Box(0, 0, w0, h, _t | _l | _b),
      _Box(x, 0, w1, h0, _t | _r),
      _Box(x, h0 + spacing, w1, h1, _r),
      _Box(x, h0 + h1 + 2 * spacing, w1, h2, _b | _r),
    ];
  }

  List<_Box> _lines() {
    final cropped = [
      for (final r in ratios)
        averageRatio > 1.1 ? r.clamp(1.0, 2.75) : r.clamp(0.6667, 1.0),
    ];
    final count = cropped.length;
    // The integer 4/3 of the width, as the family computes it.
    final targetHeight = maxWidth * 4 ~/ 3;

    double lineHeight(int offset, int itemCount) {
      var sum = 0.0;
      for (var i = offset; i < offset + itemCount; i++) {
        sum += cropped[i];
      }
      return (maxWidth - (itemCount - 1) * spacing) / sum;
    }

    final attempts = <List<int>>[
      for (var first = 1; first < count; first++)
        if (first <= 3 && count - first <= 3) [first, count - first],
      for (var first = 1; first < count - 1; first++)
        for (var second = 1; second < count - first; second++)
          if (first <= 3 &&
              second <= (averageRatio < 0.85 ? 4 : 3) &&
              count - first - second <= 3)
            [first, second, count - first - second],
      for (var first = 1; first < count - 1; first++)
        for (var second = 1; second < count - first; second++)
          for (var third = 1; third < count - first - second; third++)
            if (first <= 3 &&
                second <= 3 &&
                third <= 3 &&
                count - first - second - third <= 3)
              [first, second, third, count - first - second - third],
    ];

    List<int>? best;
    List<double>? bestHeights;
    var bestDiff = 0.0;
    for (final counts in attempts) {
      final heights = <double>[];
      var offset = 0;
      for (final c in counts) {
        heights.add(lineHeight(offset, c));
        offset += c;
      }
      final total =
          heights.fold<double>(0, (sum, h) => sum + h) +
          spacing * (counts.length - 1);
      final tooLow = heights.reduce(math.min) < minWidth ? 1.5 : 1.0;
      var shrinking = 1.0;
      for (var line = 1; line < counts.length; line++) {
        if (counts[line - 1] > counts[line]) {
          shrinking = 1.5;
          break;
        }
      }
      final diff = (total - targetHeight).abs() * tooLow * shrinking;
      if (best == null || diff < bestDiff) {
        best = counts;
        bestHeights = heights;
        bestDiff = diff;
      }
    }
    assert(best != null, 'two or more items always give one attempt');

    final boxes = <_Box>[];
    var index = 0;
    var y = 0;
    for (final (row, columns) in best!.indexed) {
      final line = bestHeights![row];
      final height = line.round();
      var x = 0;
      for (var col = 0; col < columns; col++) {
        var edges = GroupedPositionFlags.none;
        if (row == 0) edges |= _t;
        if (row == best.length - 1) edges |= _b;
        if (col == 0) edges |= _l;
        if (col == columns - 1) edges |= _r;
        // The last box takes what is left, so every line ends flush.
        final width = col == columns - 1
            ? maxWidth - x
            : (cropped[index] * line).round();
        boxes.add(_Box(x, y, width, height, edges));
        x += width + spacing;
        index++;
      }
      y += height + spacing;
    }
    return boxes;
  }
}
