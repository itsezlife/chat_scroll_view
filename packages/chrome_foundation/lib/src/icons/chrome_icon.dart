import 'package:chrome_foundation/src/icons/chrome_icon_id.dart';
import 'package:chrome_foundation/src/icons/chrome_icon_painter.dart';
import 'package:chrome_foundation/src/icons/chrome_icon_scope.dart';
import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:morphnext/morphnext.dart';

/// Draws the **chrome icon** [id] through the registry in scope.
///
/// Size and colour default to the ambient `IconTheme`. A semantic label is
/// exposed only when [semanticLabel] is given; a decorative icon stays out of
/// the semantics tree.
class ChromeIcon extends StatelessWidget {
  /// An icon for [id].
  const ChromeIcon(
    this.id, {
    this.size,
    this.color,
    this.semanticLabel,
    super.key,
  });

  /// The semantic icon id.
  final ChromeIconId id;

  /// Logical size; defaults to the icon theme size, then 24.
  final double? size;

  /// Single colour; defaults to the icon theme colour.
  final Color? color;

  /// Label announced for the icon, or null to exclude it from semantics.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painter = ChromeIconScope.of(context).painterFor(id);
    return switch (painter) {
      ChromeIconPainter$Font(:final icon) => Icon(
        icon,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      ),
      ChromeIconPainter$Paint(:final paint) => _PaintedIcon(
        paint: paint,
        size: size ?? IconTheme.of(context).size ?? _defaultSize,
        color: color ?? IconTheme.of(context).color ?? _defaultColor,
        semanticLabel: semanticLabel,
      ),
    };
  }
}

/// Draws the **chrome icon** [id] and animates when [id] changes.
///
/// Between two font glyphs the shape morphs (an interruptible spring, via
/// morphnext, which no host needs to import). Any change involving a custom
/// painted icon cross-fades over the `fade` motion role. Under instant
/// motion speed the new icon appears at once.
class AnimatedChromeIcon extends StatelessWidget {
  /// An icon for [id] that animates changes of [id].
  const AnimatedChromeIcon(
    this.id, {
    this.size,
    this.color,
    this.semanticLabel,
    super.key,
  });

  /// The semantic icon id.
  final ChromeIconId id;

  /// Logical size; defaults to the icon theme size, then 24.
  final double? size;

  /// Single colour; defaults to the icon theme colour.
  final Color? color;

  /// Label announced for the icon, or null to exclude it from semantics.
  final String? semanticLabel;

  // All font glyphs share one key so the switcher keeps one morphing widget.
  static const ValueKey<String> _fontKey = ValueKey<String>('font');

  @override
  Widget build(BuildContext context) {
    final motion = ChromeMotionScope.of(context);
    if (motion.speed.isInstant) {
      return ChromeIcon(
        id,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
    }
    final painter = ChromeIconScope.of(context).painterFor(id);
    return AnimatedSwitcher(
      duration: motion.durationOf(MotionRole.fade),
      switchInCurve: motion.curveOf(MotionRole.fade),
      switchOutCurve: motion.curveOf(MotionRole.fade),
      child: switch (painter) {
        ChromeIconPainter$Font(:final icon) => AnimatedMorphIcon(
          key: _fontKey,
          icon: icon,
          size: size,
          color: color,
          spring: MorphSprings.snappy,
          semanticLabel: semanticLabel,
        ),
        ChromeIconPainter$Paint() => ChromeIcon(
          id,
          key: ValueKey<String>(id.value),
          size: size,
          color: color,
          semanticLabel: semanticLabel,
        ),
      },
    );
  }
}

const double _defaultSize = 24;
const Color _defaultColor = Color(0xFF000000);

class _PaintedIcon extends StatelessWidget {
  const _PaintedIcon({
    required this.paint,
    required this.size,
    required this.color,
    required this.semanticLabel,
  });

  final ChromeIconPaint paint;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FunctionPainter(paint, color)),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: icon);
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(child: icon),
    );
  }
}

class _FunctionPainter extends CustomPainter {
  const _FunctionPainter(this.paintIcon, this.color);

  final ChromeIconPaint paintIcon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintIcon(canvas, size, color);

  @override
  bool shouldRepaint(_FunctionPainter oldDelegate) =>
      oldDelegate.paintIcon != paintIcon || oldDelegate.color != color;
}
