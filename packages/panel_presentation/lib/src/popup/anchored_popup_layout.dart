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
///
/// The [outset] grows the child beyond the popup on each side without moving
/// the popup: the child is the popup plus a margin, and the popup keeps the
/// place it would have had without one. The anchored popup uses it for the
/// transparent margin that still counts as the popup to the pointer.
@immutable
final class AnchoredPopupLayout extends SingleChildLayoutDelegate {
  /// A layout for a popup [width] by [height].
  const AnchoredPopupLayout({
    required this.width,
    required this.height,
    required this.textDirection,
    this.anchor,
    this.outset = EdgeInsets.zero,
  });

  /// The popup's preferred width.
  final double width;

  /// The popup's height.
  final double height;

  /// The reading direction that decides which side is the end.
  final TextDirection textDirection;

  /// The composer rectangle, in the coordinates of the box, or null.
  final Rect? anchor;

  /// The margin around the popup that the child also covers. Its left and
  /// right are the same, so the mirroring of a right-to-left layout does not
  /// change it.
  final EdgeInsets outset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(width, constraints.maxWidth) + outset.horizontal,
        height: height + outset.vertical,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final popupSize = Size(
      childSize.width - outset.horizontal,
      childSize.height - outset.vertical,
    );
    final rect =
        anchor ??
        Rect.fromLTWH(
          textDirection == TextDirection.ltr ? size.width : 0,
          size.height,
          0,
          0,
        );
    final left = textDirection == TextDirection.ltr
        ? rect.right - popupSize.width
        : rect.left;
    final maxLeft = math.max<double>(0, size.width - popupSize.width);
    return Offset(
          left.clamp(0, maxLeft),
          math.max<double>(0, rect.top - popupSize.height),
        ) -
        Offset(outset.left, outset.top);
  }

  @override
  bool shouldRelayout(AnchoredPopupLayout oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.anchor != anchor ||
      oldDelegate.outset != outset;
}
