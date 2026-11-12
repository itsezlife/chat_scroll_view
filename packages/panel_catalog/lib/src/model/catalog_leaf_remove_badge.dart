import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The **remove badge** of a hovered cell: a small cross in a translucent
/// dark box at the cell's top end corner, which a mouse click on it removes
/// the cell's content from its list (a recent, a favourite) instead of
/// picking it.
///
/// Shown only on the cell under a mouse, only where the host says the cell
/// can be removed, and drawn over the cell's content. The badge's box gets
/// darker and the cross brighter while the mouse is over the badge itself.
///
/// Two looks: [pointer] (a 14 px rounded square flush with the corner) and
/// [web] (a 16 px circle reaching 2 px past the corner).
@immutable
final class CatalogLeafRemoveBadge {
  /// A badge [extent] square at [inset] in from the cell's top and end edges
  /// (negative reaches past them), with corners of [cornerRadius] and a cross
  /// [crossExtent] wide drawn with [crossStroke].
  const CatalogLeafRemoveBadge({
    required this.extent,
    required this.cornerRadius,
    required this.crossExtent,
    required this.crossStroke,
    this.inset = 0,
    this.background = const Color(0xFF000000),
    this.backgroundOpacity = 0.3,
    this.backgroundOverOpacity = 0.5,
    this.foreground = const Color(0xFFFFFFFF),
    this.foregroundOpacity = 0.8,
    this.foregroundOverOpacity = 1,
  });

  /// The desktop look: 14 px with 3 px corners, flush with the corner; the box
  /// black at 0.3 (0.5 under the mouse), a 6 px white cross at 0.8 (1).
  static const CatalogLeafRemoveBadge pointer = CatalogLeafRemoveBadge(
    extent: 14,
    cornerRadius: 3,
    crossExtent: 6,
    crossStroke: 1.5,
  );

  /// The web look: a 16 px circle 2 px past the corner, black at 0.5 (0.7
  /// under the mouse), a 7 px white cross.
  static const CatalogLeafRemoveBadge web = CatalogLeafRemoveBadge(
    extent: 16,
    cornerRadius: 8,
    crossExtent: 7,
    crossStroke: 1.5,
    inset: -2,
    backgroundOpacity: 0.5,
    backgroundOverOpacity: 0.7,
    foregroundOpacity: 1,
  );

  /// Side of the badge's box, which is also its hit area.
  final double extent;

  /// Radius of the box's corners; half of [extent] makes a circle.
  final double cornerRadius;

  /// How far in from the cell's top and end edges the box sits.
  final double inset;

  /// Side of the cross.
  final double crossExtent;

  /// Width of the cross's strokes.
  final double crossStroke;

  /// Colour of the box, drawn at [backgroundOpacity].
  final Color background;

  /// The box's opacity while the mouse is elsewhere on the cell.
  final double backgroundOpacity;

  /// The box's opacity while the mouse is over the badge.
  final double backgroundOverOpacity;

  /// Colour of the cross, drawn at [foregroundOpacity].
  final Color foreground;

  /// The cross's opacity while the mouse is elsewhere on the cell.
  final double foregroundOpacity;

  /// The cross's opacity while the mouse is over the badge.
  final double foregroundOverOpacity;

  /// The badge's box on [cell] in [direction] (the end edge is the right in
  /// left-to-right).
  Rect rectOn(Rect cell, TextDirection direction) => Rect.fromLTWH(
    direction == TextDirection.ltr
        ? cell.right - inset - extent
        : cell.left + inset,
    cell.top + inset,
    extent,
    extent,
  );

  /// Paints the badge in [rect]; [over] while the mouse is on it.
  void paint(Canvas canvas, Rect rect, {required bool over}) {
    final backgroundAlpha = over ? backgroundOverOpacity : backgroundOpacity;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)),
      Paint()
        ..color = background.withValues(alpha: background.a * backgroundAlpha),
    );
    final half = crossExtent / 2;
    final c = rect.center;
    final foregroundAlpha = over ? foregroundOverOpacity : foregroundOpacity;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - half, c.dy - half)
        ..lineTo(c.dx + half, c.dy + half)
        ..moveTo(c.dx + half, c.dy - half)
        ..lineTo(c.dx - half, c.dy + half),
      Paint()
        ..color = foreground.withValues(alpha: foreground.a * foregroundAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = crossStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogLeafRemoveBadge &&
      other.extent == extent &&
      other.cornerRadius == cornerRadius &&
      other.inset == inset &&
      other.crossExtent == crossExtent &&
      other.crossStroke == crossStroke &&
      other.background == background &&
      other.backgroundOpacity == backgroundOpacity &&
      other.backgroundOverOpacity == backgroundOverOpacity &&
      other.foreground == foreground &&
      other.foregroundOpacity == foregroundOpacity &&
      other.foregroundOverOpacity == foregroundOverOpacity;

  @override
  int get hashCode => Object.hash(
    extent,
    cornerRadius,
    inset,
    crossExtent,
    crossStroke,
    background,
    backgroundOpacity,
    backgroundOverOpacity,
    foreground,
    foregroundOpacity,
    foregroundOverOpacity,
  );
}
