import 'package:flutter/rendering.dart';

/// A close glyph: two strokes crossing in an [extent] square centred in the
/// canvas, [strokeWidth] wide with round ends, in [color].
///
/// Stroked as one path, so a translucent colour covers the crossing once.
class ChromeCrossPainter extends CustomPainter {
  /// A cross in [color].
  const ChromeCrossPainter(
    this.color, {
    this.extent = 12,
    this.strokeWidth = 2,
  });

  /// The colour of the strokes.
  final Color color;

  /// The side of the square the cross spans.
  final double extent;

  /// The width of the strokes.
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: extent,
      height: extent,
    );
    final cross = Path()
      ..moveTo(box.left, box.top)
      ..lineTo(box.right, box.bottom)
      ..moveTo(box.right, box.top)
      ..lineTo(box.left, box.bottom);
    canvas.drawPath(cross, pen);
  }

  @override
  bool shouldRepaint(ChromeCrossPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.extent != extent ||
      oldDelegate.strokeWidth != strokeWidth;
}
