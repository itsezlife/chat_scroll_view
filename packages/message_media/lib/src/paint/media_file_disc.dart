import 'package:flutter/widgets.dart';

/// The disc a file row without a picture draws in its control slot: a
/// filled circle of [color] with a document glyph in [iconColor].
///
/// It is the file's picture: the status control (download, progress,
/// cancel) draws over it while the file is not on the device, and it shows
/// alone once the file is. Every platform fills it with one colour for the
/// conversation side, never by the file's extension.
class MediaFileDisc extends StatelessWidget {
  /// A disc of [color] with the glyph in [iconColor].
  const MediaFileDisc({
    required this.color,
    this.iconColor = const Color(0xFFFFFFFF),
    super.key,
  });

  /// The disc's fill.
  final Color color;

  /// The glyph's colour.
  final Color iconColor;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DiscPainter(color, iconColor));
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter(this.color, this.iconColor);

  final Color color;
  final Color iconColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(centre, radius, Paint()..color = color);
    // A page with a folded corner, 0.36 of the disc wide and 0.46 high.
    final w = size.shortestSide * 0.36;
    final h = size.shortestSide * 0.46;
    final fold = w * 0.38;
    final page = Rect.fromCenter(center: centre, width: w, height: h);
    final r = w * 0.12;
    final outline = Path()
      ..moveTo(page.left + r, page.top)
      ..lineTo(page.right - fold, page.top)
      ..lineTo(page.right, page.top + fold)
      ..lineTo(page.right, page.bottom - r)
      ..quadraticBezierTo(page.right, page.bottom, page.right - r, page.bottom)
      ..lineTo(page.left + r, page.bottom)
      ..quadraticBezierTo(page.left, page.bottom, page.left, page.bottom - r)
      ..lineTo(page.left, page.top + r)
      ..quadraticBezierTo(page.left, page.top, page.left + r, page.top)
      ..close();
    final corner = Path()
      ..moveTo(page.right - fold, page.top)
      ..lineTo(page.right - fold, page.top + fold)
      ..lineTo(page.right, page.top + fold);
    final stroke = Paint()
      ..color = iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.045
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(outline, stroke)
      ..drawPath(corner, stroke);
  }

  @override
  bool shouldRepaint(_DiscPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.iconColor != iconColor;
}
