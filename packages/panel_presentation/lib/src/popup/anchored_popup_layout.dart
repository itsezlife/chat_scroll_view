import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// Places an anchored popup above the composer, its end edge on the
/// composer's end edge.
///
/// Positions the child in a box of [size]: the child is [width] wide (narrower
/// in a narrow box) and [height] tall; its bottom edge is on the anchor's top
/// edge and its end edge on the anchor's end edge, mirrored in a
/// right-to-left layout. It stays inside the box horizontally and never
/// starts above it. Without an anchor the popup sits in the bottom-end corner
/// of the box.
@immutable
final class AnchoredPopupLayout extends SingleChildLayoutDelegate {
  /// A layout for a popup [width] by [height].
  const AnchoredPopupLayout({
    required this.width,
    required this.height,
    required this.textDirection,
    this.anchor,
  });

  /// The popup's preferred width.
  final double width;

  /// The popup's height.
  final double height;

  /// The reading direction that decides which side is the end.
  final TextDirection textDirection;

  /// The composer rectangle, in the coordinates of the box, or null.
  final Rect? anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(width, constraints.maxWidth),
        height: height,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rect =
        anchor ??
        Rect.fromLTWH(
          textDirection == TextDirection.ltr ? size.width : 0,
          size.height,
          0,
          0,
        );
    final left = textDirection == TextDirection.ltr
        ? rect.right - childSize.width
        : rect.left;
    final maxLeft = math.max<double>(0, size.width - childSize.width);
    return Offset(
      left.clamp(0, maxLeft),
      math.max<double>(0, rect.top - childSize.height),
    );
  }

  @override
  bool shouldRelayout(AnchoredPopupLayout oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.anchor != anchor;
}
