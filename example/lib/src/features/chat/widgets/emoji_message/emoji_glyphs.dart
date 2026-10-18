import 'dart:math' as math;

import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart'
    show EmojiSendState;
import 'package:flutter/rendering.dart';

/// Paints the delivery state of the pill: the clock, one check, two checks, or
/// the error square, right-aligned in the box it is given.
///
/// Two check designs exist. Android's is a 12 x 12 bitmap, a full check and a
/// half check 4.8 dp apart (`msg_check_s`, `msg_halfcheck_s`); the path here
/// is traced from the bitmap at its 3x size (1.5 stroke, round caps). iOS draws
/// vectors: an 11 x 9 canvas scaled, a 0.99 stroke, a full check and a partial
/// one 6 pt apart (`generateCheckImage`). Desktop's sprites are not in the
/// sources at hand and use Android's.
class EmojiTicksPainter extends CustomPainter {
  /// Paints [state] in [color].
  const EmojiTicksPainter({
    required this.state,
    required this.color,
    required this.vector,
    this.errorColor = const Color(0xFFDB3535),
  });

  /// What to draw.
  final EmojiSendState state;

  /// The colour of the checks and the clock.
  final Color color;

  /// Whether the checks are iOS's vector ones.
  final bool vector;

  /// The error square's fill (`key_chat_sentError`).
  final Color errorColor;

  // Android: the check, in a 12 x 12 box.
  static final Path _androidFull = Path()
    ..moveTo(1.25, 6.9)
    ..lineTo(3.75, 9.5)
    ..lineTo(10.75, 2.6);
  static final Path _androidHalf = Path()
    ..moveTo(2.4, 8.7)
    ..lineTo(3.75, 9.6)
    ..lineTo(10.75, 2.6);

  // iOS: `generateCheckImage`, after its translate(1, 1), in an 11 x 9 box.
  static final Path _iosFull = Path()
    ..moveTo(1, 5)
    ..lineTo(3.95157047, 7.95157047)
    ..cubicTo(
      3.97734507,
      7.97734507,
      4.01913396,
      7.97734507,
      4.04490857,
      7.95157047,
    )
    ..cubicTo(
      4.04548448,
      7.95099456,
      4.04604969,
      7.95040803,
      4.04660389,
      7.9498112,
    )
    ..lineTo(10.5, 1);
  static final Path _iosPartial = Path()
    ..moveTo(1.5, 8)
    ..lineTo(8, 1);

  @override
  void paint(Canvas canvas, Size size) {
    switch (state) {
      case EmojiSendState.none:
        return;
      case EmojiSendState.sending:
        _clock(canvas, size);
      case EmojiSendState.sent:
        _check(canvas, size, full: true, dx: 0);
      case EmojiSendState.read:
        _read(canvas, size);
      case EmojiSendState.error:
        _error(canvas, size);
    }
  }

  void _read(Canvas canvas, Size size) {
    // The status box holds both checks: the first at its start, the second
    // `gap` after it.
    final checkWidth = vector ? 11.0 : 12.0;
    final gap = size.width - checkWidth;
    _check(canvas, size, full: true, dx: 0);
    _check(canvas, size, full: false, dx: gap);
  }

  void _check(
    Canvas canvas,
    Size size, {
    required bool full,
    required double dx,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = vector ? 0.99 : 1.5;
    final path = vector
        ? (full ? _iosFull : _iosPartial)
        : (full ? _androidFull : _androidHalf);
    canvas
      ..save()
      ..translate(dx, 0)
      ..drawPath(path, paint)
      ..restore();
  }

  void _clock(Canvas canvas, Size size) {
    const stroke = 1.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    canvas
      ..drawCircle(center, (side - stroke) / 2, paint)
      ..drawLine(center, center.translate(0, -side * 0.27), paint)
      ..drawLine(center, center.translate(side * 0.2, 0), paint);
  }

  void _error(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      Paint()..color = errorColor,
    );
    final mark = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    canvas
      ..drawLine(
        Offset(x, size.height * 0.25),
        Offset(x, size.height * 0.6),
        mark,
      )
      ..drawCircle(Offset(x, size.height * 0.78), 0.8, mark);
  }

  @override
  bool shouldRepaint(EmojiTicksPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.vector != vector ||
      oldDelegate.errorColor != errorColor;
}

/// Paints the views icon (an eye) in [color]: the reference's 17 x 12 bitmap,
/// an almond with a ring and a pupil, redrawn as a path.
class EmojiViewsIconPainter extends CustomPainter {
  /// Paints the icon in [color].
  const EmojiViewsIconPainter({required this.color});

  /// The icon's colour.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final almond = Path()
      ..moveTo(0, h / 2)
      ..quadraticBezierTo(w / 2, -h * 0.45, w, h / 2)
      ..quadraticBezierTo(w / 2, h * 1.45, 0, h / 2)
      ..close();
    final center = Offset(w / 2, h / 2);
    // Even-odd: the almond, a hole for the ring, the pupil filled again.
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(almond, Offset.zero)
      ..addOval(Rect.fromCircle(center: center, radius: h * 0.31))
      ..addOval(Rect.fromCircle(center: center, radius: h * 0.21));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(EmojiViewsIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
