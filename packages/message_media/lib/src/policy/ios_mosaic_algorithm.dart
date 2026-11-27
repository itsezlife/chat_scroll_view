import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/policy/media_box_sizing.dart';
import 'package:message_media/src/policy/mosaic_algorithm.dart';
import 'package:meta/meta.dart';

/// The iOS family's mosaic: a fixed pattern per orientation mix for two to
/// four boxes, else the best of every split into two to four rows.
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [compactMaxSize] | 300 × 380 | Max mosaic on a compact list |
/// | [regularMaxSize] | 440 × 440 | Max mosaic on a regular list |
/// | [compactMaxListWidth] | 680 | Widest list that is compact |
/// | [cellGap] | 1 | Seam between boxes |
/// | [minCellWidth] | 68 | Floor of a narrow box's width; a first row shorter than it scores worse |
/// | [minCellHeight] | 81 | Floor of the lower row's height under a wide first box of four |
///
/// The max mosaic is the list class's max size scaled down (never up) to
/// the block width, so a narrow bubble keeps the max size's proportions.
///
/// ## Orientation and patterns
///
/// Each box is wide (aspect over 1.2), narrow (under 0.8) or square. With
/// two to four boxes and none wider than 2:1, the mix picks a pattern:
///
/// | Boxes | Mix | Pattern |
/// | --- | --- | --- |
/// | 2 | both wide, much wider than the max mosaic | stacked, full width |
/// | 2 | both wide or both square | side by side, equal widths |
/// | 2 | otherwise | side by side, widths by aspect |
/// | 3 | first narrow | the first a full-height column, two stacked beside it |
/// | 3 | otherwise | the first full width, two side by side under it |
/// | 4 | first wide | the first full width, three in a row under it |
/// | 4 | otherwise | the first a full-height column, three stacked beside it |
///
/// ## Rows
///
/// Five or more boxes, or any box wider than 2:1, are laid in rows. Each
/// box's aspect is pulled toward the album's (at least 1 when the album is
/// wide, at most 1 otherwise) and held in 2:3 to 1.7. Every split into two,
/// three or four rows of at most three boxes (four in the middle row of a
/// narrow album) is scored by how far its height lands from 4/3 of the
/// width; a split with a row holding more boxes than the row under it, or
/// whose first row is shorter than [minCellWidth], scores worse. The last box of each row stretches to the
/// widest row.
///
/// A box without dimensions is a square. A pattern that leaves a box with
/// no area (very narrow boxes beside a wide one) is laid in rows instead,
/// reported as `media` / `layoutFallback` with the rule
/// [MediaLayoutFallbackRule.mosaicRows].
@immutable
final class IosMosaicAlgorithm implements MosaicAlgorithm {
  /// The iOS mosaic; any value can be replaced.
  const IosMosaicAlgorithm({
    this.compactMaxSize = const Size(300, 380),
    this.regularMaxSize = const Size(440, 440),
    this.compactMaxListWidth = 680,
    this.cellGap = 1,
    this.minCellWidth = 68,
    this.minCellHeight = 81,
  });

  /// See the class table.
  final Size compactMaxSize;

  /// See the class table.
  final Size regularMaxSize;

  /// See the class table.
  final double compactMaxListWidth;

  /// See the class table.
  final double cellGap;

  /// See the class table.
  final double minCellWidth;

  /// See the class table.
  final double minCellHeight;

  // Orientation thresholds and the rows' aspect clamp: properties of the
  // algorithm's shape, not values a host tunes.
  static const double _wideAbove = 1.2;
  static const double _narrowBelow = 0.8;
  static const double _rowsAbove = 2;
  static const double _stackedFactor = 1.4;
  static const double _minRowAspect = 0.66667;
  static const double _maxRowAspect = 1.7;

  @override
  String get name => 'ios';

  /// The max mosaic for a block [width] wide in a list [listWidth] wide.
  Size maxSizeFor({required double width, required double listWidth}) {
    final max = listWidth <= compactMaxListWidth
        ? compactMaxSize
        : regularMaxSize;
    final scale = math.min<double>(1, width / math.max(1, max.width));
    return Size(
      (max.width * scale).floorToDouble(),
      (max.height * scale).floorToDouble(),
    );
  }

  @override
  MosaicArrangement arrange({
    required List<MediaItem> items,
    required double width,
    required MediaLayoutInput input,
  }) {
    final maxSize = maxSizeFor(width: width, listWidth: input.availableWidth);
    final ratios = [
      for (final item in items)
        switch (item.descriptor.size) {
          ContentSize(:final width, :final height) => width / height,
          null => 1.0,
        },
    ];
    final forceRows = ratios.any((ratio) => ratio > _rowsAbove);
    var frames = forceRows || items.length > 4
        ? null
        : _pattern(ratios, maxSize);
    if (frames != null && frames.any((f) => f.rect.isEmpty)) {
      for (final (index, frame) in frames.indexed) {
        if (!frame.rect.isEmpty) continue;
        _reportRows(input, items[index], frame.rect.size);
      }
      frames = null;
    }
    frames ??= _rows(ratios, maxSize);
    var size = Size.zero;
    for (final frame in frames) {
      size = Size(
        math.max(size.width, frame.rect.right.roundToDouble()),
        math.max(size.height, frame.rect.bottom.roundToDouble()),
      );
    }
    return MosaicArrangement(
      size: size,
      placements: [
        for (final (index, frame) in frames.indexed)
          MosaicPlacement(
            itemId: items[index].id,
            rect: frame.rect,
            edges: frame.edges,
          ),
      ],
    );
  }

  // --- Patterns: two to four boxes ---

  /// The fixed pattern for [r] (two to four aspects), or null when none
  /// applies.
  List<_Frame>? _pattern(List<double> r, Size maxSize) {
    final mw = maxSize.width;
    final mh = maxSize.height;
    final gap = cellGap;
    final mix = r.map(_orientationOf).join();
    final average = _averageOf(r);
    switch (r.length) {
      case 2:
        if (mix == 'ww' &&
            average > _stackedFactor * (mw / mh) &&
            r[1] - r[0] < 0.2) {
          final h = math
              .min(mw / r[0], math.min(mw / r[1], (mh - gap) / 2))
              .floorToDouble();
          return [
            _Frame(Rect.fromLTWH(0, 0, mw, h), _top | _left | _right),
            _Frame(Rect.fromLTWH(0, h + gap, mw, h), _bottom | _left | _right),
          ];
        }
        if (mix == 'ww' || mix == 'qq') {
          final w = (mw - gap) / 2;
          final h = math.min(w / r[0], math.min(w / r[1], mh)).floorToDouble();
          return [
            _Frame(Rect.fromLTWH(0, 0, w, h), _top | _left | _bottom),
            _Frame(Rect.fromLTWH(w + gap, 0, w, h), _top | _right | _bottom),
          ];
        }
        final second = math
            .min(
              0.5 * (mw - gap),
              ((mw - gap) / r[0] / (1 / r[0] + 1 / r[1])).roundToDouble(),
            )
            .floorToDouble();
        final first = mw - second - gap;
        final h = math
            .min(mh, math.min(first / r[0], second / r[1]).roundToDouble())
            .floorToDouble();
        return [
          _Frame(Rect.fromLTWH(0, 0, first, h), _top | _left | _bottom),
          _Frame(
            Rect.fromLTWH(first + gap, 0, second, h),
            _top | _right | _bottom,
          ),
        ];
      case 3:
        if (mix.startsWith('n')) {
          final firstH = mh;
          final thirdH = math.min(
            (mh - gap) * 0.5,
            (r[1] * (mw - gap) / (r[2] + r[1])).roundToDouble(),
          );
          final secondH = mh - thirdH - gap;
          final rightW = math.max(
            minCellWidth,
            math.min(
              (mw - gap) * 0.5,
              math.min(thirdH * r[2], secondH * r[1]).roundToDouble(),
            ),
          );
          final leftW = math
              .min(firstH * r[0], mw - gap - rightW)
              .roundToDouble();
          return [
            _Frame(Rect.fromLTWH(0, 0, leftW, firstH), _top | _left | _bottom),
            _Frame(
              Rect.fromLTWH(leftW + gap, 0, rightW, secondH),
              _right | _top,
            ),
            _Frame(
              Rect.fromLTWH(leftW + gap, secondH + gap, rightW, thirdH),
              _right | _bottom,
            ),
          ];
        }
        final firstH = math.min(mw / r[0], (mh - gap) * 0.66).floorToDouble();
        final w = (mw - gap) / 2;
        final secondH = math.min(
          mh - firstH - gap,
          math.min(w / r[1], w / r[2]).roundToDouble(),
        );
        return [
          _Frame(Rect.fromLTWH(0, 0, mw, firstH), _top | _left | _right),
          _Frame(Rect.fromLTWH(0, firstH + gap, w, secondH), _left | _bottom),
          _Frame(
            Rect.fromLTWH(w + gap, firstH + gap, w, secondH),
            _right | _bottom,
          ),
        ];
      case 4:
        if (mix.startsWith('w')) {
          final h0 = math.min(mw / r[0], (mh - gap) * 0.66).roundToDouble();
          var h = ((mw - 2 * gap) / (r[1] + r[2] + r[3])).roundToDouble();
          final w0 = math.max(
            minCellWidth,
            math.min((mw - 2 * gap) * 0.4, h * r[1]),
          );
          final w2 = math.max(
            math.max(minCellWidth, (mw - 2 * gap) * 0.33),
            h * r[3],
          );
          final w1 = mw - w0 - w2 - 2 * gap;
          h = math.max(minCellHeight, math.min(mh - h0 - gap, h));
          final y = h0 + gap;
          return [
            _Frame(Rect.fromLTWH(0, 0, mw, h0), _top | _left | _right),
            _Frame(Rect.fromLTWH(0, y, w0, h), _left | _bottom),
            _Frame(Rect.fromLTWH(w0 + gap, y, w1, h), _bottom),
            _Frame(
              Rect.fromLTWH(w0 + w1 + 2 * gap, y, w2, h),
              _right | _bottom,
            ),
          ];
        }
        final h = mh;
        final w0 = math.min(h * r[0], (mw - gap) * 0.6).roundToDouble();
        var w = ((mh - 2 * gap) / (1 / r[1] + 1 / r[2] + 1 / r[3]))
            .roundToDouble();
        final h0 = (w / r[1]).floorToDouble();
        final h1 = (w / r[2]).floorToDouble();
        final h2 = h - h0 - h1 - 2 * gap;
        w = math.max(minCellWidth, math.min(mw - w0 - gap, w));
        final x = w0 + gap;
        return [
          _Frame(Rect.fromLTWH(0, 0, w0, h), _top | _left | _bottom),
          _Frame(Rect.fromLTWH(x, 0, w, h0), _right | _top),
          _Frame(Rect.fromLTWH(x, h0 + gap, w, h1), _right),
          _Frame(Rect.fromLTWH(x, h0 + h1 + 2 * gap, w, h2), _right | _bottom),
        ];
    }
    return null;
  }

  // --- Rows: five or more boxes, or a box wider than 2:1 ---

  List<_Frame> _rows(List<double> ratios, Size maxSize) {
    final gap = cellGap;
    final count = ratios.length;
    final average = _averageOf(ratios);
    final cropped = [
      for (final ratio in ratios)
        (average > 1.1
                ? math.max<double>(1, ratio)
                : math.min<double>(1, ratio))
            .clamp(_minRowAspect, _maxRowAspect)
            .toDouble(),
    ];

    double heightOf(int start, int end) {
      var sum = 0.0;
      for (var i = start; i < end; i++) {
        sum += cropped[i];
      }
      return (maxSize.width - (end - start - 1) * gap) / sum;
    }

    final splits = <List<int>>[];
    for (var first = 1; first < count; first++) {
      if (first > 3 || count - first > 3) continue;
      splits.add([first, count - first]);
    }
    final middleMax = average < 0.85 ? 4 : 3;
    for (var first = 1; first < count - 1; first++) {
      for (var second = 1; second < count - first; second++) {
        final third = count - first - second;
        if (first > 3 || second > middleMax || third > 3) continue;
        splits.add([first, second, third]);
      }
    }
    for (var first = 1; first < count - 2; first++) {
      for (var second = 1; second < count - first; second++) {
        for (var third = 1; third < count - first - second; third++) {
          final fourth = count - first - second - third;
          if (first > 3 || second > 3 || third > 3 || fourth > 3) continue;
          splits.add([first, second, third, fourth]);
        }
      }
    }

    final targetHeight = (maxSize.width / 3 * 4).floorToDouble();
    List<int>? best;
    List<double>? bestHeights;
    var bestScore = 0.0;
    for (final split in splits) {
      final heights = <double>[];
      var start = 0;
      for (final n in split) {
        heights.add(heightOf(start, start + n));
        start += n;
      }
      // The first row's height as it stands after the gaps: the score
      // compares that running total, so a split never scores its own
      // shortest row.
      var total = gap * (split.length - 1);
      var firstRowTotal = double.infinity;
      for (final h in heights) {
        total += h.floorToDouble();
        firstRowTotal = math.min(firstRowTotal, total);
      }
      var score = (total - targetHeight).abs();
      if (split.length > 1 &&
          (split[0] > split[1] ||
              (split.length > 2 && split[1] > split[2]) ||
              (split.length > 3 && split[2] > split[3]))) {
        score *= 1.5;
      }
      if (firstRowTotal < minCellWidth) score *= 1.5;
      if (best == null || score < bestScore) {
        best = split;
        bestHeights = heights;
        bestScore = score;
      }
    }

    final frames = <_Frame>[];
    var y = 0.0;
    var index = 0;
    for (final (row, n) in best!.indexed) {
      final h = bestHeights![row].ceilToDouble();
      var x = 0.0;
      for (var k = 0; k < n; k++) {
        var edges = GroupedPositionFlags.none;
        if (row == 0) edges |= _top;
        if (row == best.length - 1) edges |= _bottom;
        if (k == 0) edges |= _left;
        if (k == n - 1) edges |= _right;
        final w = (cropped[index] * h).ceilToDouble();
        frames.add(_Frame(Rect.fromLTWH(x, y, w, h), edges));
        x += w + gap;
        index++;
      }
      y += h + gap;
    }
    // Rows round up box by box, so their right ends differ: each row's last
    // box reaches the widest.
    final right = frames
        .where((f) => f.edges.hasRight)
        .fold<double>(0, (r, f) => math.max(r, f.rect.right));
    return [
      for (final frame in frames)
        frame.edges.hasRight && frame.rect.right < right
            ? _Frame(
                Rect.fromLTRB(
                  frame.rect.left,
                  frame.rect.top,
                  right,
                  frame.rect.bottom,
                ),
                frame.edges,
              )
            : frame,
    ];
  }

  // --- Shared ---

  static const _top = GroupedPositionFlags.top;
  static const _bottom = GroupedPositionFlags.bottom;
  static const _left = GroupedPositionFlags.left;
  static const _right = GroupedPositionFlags.right;

  static String _orientationOf(double ratio) => switch (ratio) {
    > _wideAbove => 'w',
    < _narrowBelow => 'n',
    _ => 'q',
  };

  /// The album's aspect as the algorithm measures it: one more than the
  /// sum of the aspects, over their count. The extra one is part of the
  /// shape (it tips a two-box album toward wide), not an off-by-one.
  static double _averageOf(List<double> ratios) =>
      ratios.fold<double>(1, (sum, r) => sum + r) / ratios.length;

  static void _reportRows(MediaLayoutInput input, MediaItem item, Size size) {
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.media,
      MediaOp.layoutFallback,
      correlation: ChatCorrelation(
        chatId: input.correlation.chatId,
        scrollId: input.correlation.scrollId,
        clientMessageId: input.correlation.clientMessageId,
        mediaItemId: item.id.toString(),
      ),
      fields: () => {
        'rule': MediaLayoutFallbackRule.mosaicRows,
        'width': size.width,
        'height': size.height,
      },
    );
  }

  /// A copy with the given values replaced.
  IosMosaicAlgorithm copyWith({
    Size? compactMaxSize,
    Size? regularMaxSize,
    double? compactMaxListWidth,
    double? cellGap,
    double? minCellWidth,
    double? minCellHeight,
  }) => IosMosaicAlgorithm(
    compactMaxSize: compactMaxSize ?? this.compactMaxSize,
    regularMaxSize: regularMaxSize ?? this.regularMaxSize,
    compactMaxListWidth: compactMaxListWidth ?? this.compactMaxListWidth,
    cellGap: cellGap ?? this.cellGap,
    minCellWidth: minCellWidth ?? this.minCellWidth,
    minCellHeight: minCellHeight ?? this.minCellHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is IosMosaicAlgorithm &&
      other.compactMaxSize == compactMaxSize &&
      other.regularMaxSize == regularMaxSize &&
      other.compactMaxListWidth == compactMaxListWidth &&
      other.cellGap == cellGap &&
      other.minCellWidth == minCellWidth &&
      other.minCellHeight == minCellHeight;

  @override
  int get hashCode => Object.hash(
    compactMaxSize,
    regularMaxSize,
    compactMaxListWidth,
    cellGap,
    minCellWidth,
    minCellHeight,
  );
}

/// One box before it is keyed by its item.
final class _Frame {
  const _Frame(this.rect, this.edges);

  final Rect rect;
  final GroupedPositionFlags edges;
}
