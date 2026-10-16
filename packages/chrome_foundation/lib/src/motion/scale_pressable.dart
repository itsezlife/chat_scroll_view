import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/motion/overshoot_curve.dart';
import 'package:flutter/widgets.dart';

/// A hit target that shrinks while pressed and overshoots back on release.
///
/// Timing comes from the `press` and `release` motion roles, so a
/// `ChromeMotionScope` speed (including instant) applies.
class ScalePressable extends StatefulWidget {
  /// Creates a press-scaled hit target.
  const ScalePressable({
    required this.onPressed,
    required this.child,
    this.pressedScaleReduction = 0.1,
    this.releaseTension,
    super.key,
  });

  /// Tap handler; null disables both the tap and the scale.
  final VoidCallback? onPressed;

  /// Child painted under a scale transition.
  final Widget child;

  /// Subtracted from `1.0` while pressed (`0.1` for actions, `0.025` for
  /// tabs).
  final double pressedScaleReduction;

  /// [OvershootCurve] tension on release (`1.5` for actions, `1.2` for tabs);
  /// null plays the `release` role's own curve.
  final double? releaseTension;

  @override
  State<ScalePressable> createState() => _ScalePressableState();
}

class _ScalePressableState extends State<ScalePressable>
    with SingleTickerProviderStateMixin {
  // Bounds reach past 1 so the release can overshoot; a default controller
  // would clamp the curve at 1.
  late final AnimationController _scale = AnimationController(
    vsync: this,
    value: 1,
    lowerBound: 0.8,
    upperBound: 1.2,
  );

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _press() {
    final spec = ChromeMotionScope.of(context).specOf(MotionRole.press);
    _scale.animateTo(
      1 - widget.pressedScaleReduction,
      duration: spec.duration,
      curve: spec.curve,
    );
  }

  void _release() {
    final spec = ChromeMotionScope.of(context).specOf(MotionRole.release);
    final tension = widget.releaseTension;
    _scale.animateTo(
      1,
      duration: spec.duration,
      curve: tension == null ? spec.curve : OvershootCurve(tension),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _press() : null,
      onTapUp: enabled ? (_) => _release() : null,
      onTapCancel: enabled ? _release : null,
      onTap: widget.onPressed,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
