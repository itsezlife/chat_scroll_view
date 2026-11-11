import 'package:flutter/rendering.dart';

/// A more-options glyph: three dots of [radius] in a column, [spacing]
/// apart centre to centre, centred in the canvas, in [color].
class ChromeDotsPainter extends CustomPainter {
  /// Three dots in [color].
  const ChromeDotsPainter(this.color, {this.radius = 2, this.spacing = 6});

  /// The colour of the dots.
  final Color color;

  /// The radius of a dot.
  final double radius;

  /// The distance between the centres of two neighbouring dots.
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final centre = size.center(Offset.zero);
    for (final dy in [-spacing, 0.0, spacing]) {
      canvas.drawCircle(centre.translate(0, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(ChromeDotsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.spacing != spacing;
}
