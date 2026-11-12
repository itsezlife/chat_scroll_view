import 'dart:math' as math;

import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/widgets.dart';

/// A busy indicator: a three-quarter arc in the accent turning once every
/// [turnPeriod], in an [extent] square.
///
/// The arc is [strokeWidth] wide with round ends, inset [inset] from the
/// square. Under an instant motion speed (reduce motion) it stands still. It
/// is a semantics container, not a button: nothing here takes input.
class ChromeSpinner extends StatefulWidget {
  /// A spinner.
  const ChromeSpinner({
    this.extent = defaultExtent,
    this.strokeWidth = 3,
    this.inset = 4,
    super.key,
  });

  /// The side of the square: 40.
  static const double defaultExtent = 40;

  /// How long one turn takes. A loop, not a transition: a speed does not
  /// scale it, an instant one stops it.
  static const Duration turnPeriod = Duration(seconds: 1);

  /// The side of the square.
  final double extent;

  /// The width of the arc.
  final double strokeWidth;

  /// How far the arc is inset from the square.
  final double inset;

  @override
  State<ChromeSpinner> createState() => _ChromeSpinnerState();
}

class _ChromeSpinnerState extends State<ChromeSpinner>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: ChromeSpinner.turnPeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    if (speed == null || !speed.isInstant) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: SizedBox.square(
      dimension: widget.extent,
      child: CustomPaint(
        painter: _ArcPainter(
          _turn,
          ChromeThemeScope.paletteOf(context).accent,
          strokeWidth: widget.strokeWidth,
          inset: widget.inset,
        ),
      ),
    ),
  );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(
    this.turn,
    this.color, {
    required this.strokeWidth,
    required this.inset,
  }) : super(repaint: turn);

  final Animation<double> turn;
  final Color color;
  final double strokeWidth;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      (Offset.zero & size).deflate(inset),
      turn.value * 2 * math.pi,
      math.pi * 1.5,
      false,
      pen,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.inset != inset;
}
