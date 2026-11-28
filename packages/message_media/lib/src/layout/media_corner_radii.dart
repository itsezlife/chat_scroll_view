import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// The four corner radii of a media cell, in logical pixels, each its own
/// number so two layouts interpolate corner by corner.
///
/// Corners are physical (left / right), as a cell's rect is.
@immutable
final class MediaCornerRadii {
  /// Radii of each corner.
  const MediaCornerRadii({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  }) : assert(
         topLeft >= 0 && topRight >= 0 && bottomLeft >= 0 && bottomRight >= 0,
         'A corner radius is not negative.',
       );

  /// Every corner [radius].
  const MediaCornerRadii.all(double radius)
    : this(
        topLeft: radius,
        topRight: radius,
        bottomLeft: radius,
        bottomRight: radius,
      );

  /// The radii [t] of the way from [a] to [b], corner by corner; a curve
  /// that overshoots never takes a corner below 0.
  factory MediaCornerRadii.lerp(
    MediaCornerRadii a,
    MediaCornerRadii b,
    double t,
  ) => MediaCornerRadii(
    topLeft: math.max(0, lerpDouble(a.topLeft, b.topLeft, t)!),
    topRight: math.max(0, lerpDouble(a.topRight, b.topRight, t)!),
    bottomLeft: math.max(0, lerpDouble(a.bottomLeft, b.bottomLeft, t)!),
    bottomRight: math.max(0, lerpDouble(a.bottomRight, b.bottomRight, t)!),
  );

  /// Square corners: what a cell has until the paint step resolves them.
  static const zero = MediaCornerRadii.all(0);

  /// The top-left corner.
  final double topLeft;

  /// The top-right corner.
  final double topRight;

  /// The bottom-left corner.
  final double bottomLeft;

  /// The bottom-right corner.
  final double bottomRight;

  /// [rect] rounded by these radii.
  RRect toRRect(Rect rect) => RRect.fromRectAndCorners(
    rect,
    topLeft: Radius.circular(topLeft),
    topRight: Radius.circular(topRight),
    bottomLeft: Radius.circular(bottomLeft),
    bottomRight: Radius.circular(bottomRight),
  );

  @override
  bool operator ==(Object other) =>
      other is MediaCornerRadii &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);

  @override
  String toString() =>
      'MediaCornerRadii($topLeft, $topRight, $bottomLeft, $bottomRight)';
}
