import 'package:flutter/widgets.dart';

/// Draws a custom icon: paint into [canvas] within `Offset.zero & size`, using
/// [color] as the icon's single colour.
typedef ChromeIconPaint = void Function(Canvas canvas, Size size, Color color);

/// How one **chrome icon** is drawn.
///
/// Two forms: a font glyph, which can morph into another font glyph, and a
/// custom paint callback, which cross-fades. Hosts register either for their
/// own ids.
@immutable
sealed class ChromeIconPainter {
  const ChromeIconPainter();

  /// A glyph from an icon font. Two font painters morph into each other.
  const factory ChromeIconPainter.font(IconData icon) = ChromeIconPainter$Font;

  /// A custom painted icon.
  ///
  /// [paint] must be a stable function: a different callback is a different
  /// painter, and the icon repaints when it changes.
  const factory ChromeIconPainter.paint(ChromeIconPaint paint) =
      ChromeIconPainter$Paint;
}

/// A [ChromeIconPainter] backed by an icon-font glyph.
final class ChromeIconPainter$Font extends ChromeIconPainter {
  /// A painter for [icon].
  const ChromeIconPainter$Font(this.icon);

  /// The glyph.
  final IconData icon;

  @override
  bool operator ==(Object other) =>
      other is ChromeIconPainter$Font && other.icon == icon;

  @override
  int get hashCode => icon.hashCode;
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
