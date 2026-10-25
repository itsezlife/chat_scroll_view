import 'package:flutter/widgets.dart';

/// Draws a custom icon: paint into [canvas] within `Offset.zero & size`, using
/// [color] as the icon's single colour.
typedef ChromeIconPaint = void Function(Canvas canvas, Size size, Color color);

/// How one **chrome icon** is drawn.
///
/// Two forms: a font glyph, which can morph into another font glyph, and a
/// custom paint callback, which cross-fades. Hosts register either for their
/// own ids.
///
/// A font glyph can be turned and scaled within its icon box, so a host whose
/// icon set needs a tilted glyph (a send arrow pointing up a little) or a
/// smaller one (an icon font that fills its em box) keeps the morph.
@immutable
sealed class ChromeIconPainter {
  const ChromeIconPainter();

  /// A glyph from an icon font. Two font painters morph into each other.
  ///
  /// The glyph is turned clockwise by [turn] radians about the centre of the
  /// icon box and drawn at [scale] times the box's size; the box keeps the
  /// size it is given. Between two font painters the turn animates with the
  /// morph.
  const factory ChromeIconPainter.font(
    IconData icon, {
    double turn,
    double scale,
  }) = ChromeIconPainter$Font;

  /// A custom painted icon.
  ///
  /// [paint] must be a stable function: a different callback is a different
  /// painter, and the icon repaints when it changes.
  const factory ChromeIconPainter.paint(ChromeIconPaint paint) =
      ChromeIconPainter$Paint;
}

/// A [ChromeIconPainter] backed by an icon-font glyph.
final class ChromeIconPainter$Font extends ChromeIconPainter {
  /// A painter for [icon], turned by [turn] and drawn at [scale].
  const ChromeIconPainter$Font(this.icon, {this.turn = 0, this.scale = 1})
    : assert(scale > 0, 'a glyph needs a positive scale');

  /// The glyph.
  final IconData icon;

  /// Clockwise turn in radians about the centre of the icon box.
  final double turn;

  /// The drawn glyph's size as a fraction of the icon box.
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is ChromeIconPainter$Font &&
      other.icon == icon &&
      other.turn == turn &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(icon, turn, scale);
}

/// A [ChromeIconPainter] backed by a paint callback.
final class ChromeIconPainter$Paint extends ChromeIconPainter {
  /// A painter calling [paint].
  const ChromeIconPainter$Paint(this.paint);

  /// Draws the icon.
  final ChromeIconPaint paint;

  @override
  bool operator ==(Object other) =>
      other is ChromeIconPainter$Paint && other.paint == paint;

  @override
  int get hashCode => paint.hashCode;
}
