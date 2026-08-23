import 'package:flutter/material.dart';

/// Shrink on press, overshoot on release.
class ScalePressable extends StatefulWidget {
  /// Creates a press-scaled hit target.
  const ScalePressable({
    required this.onPressed,
    required this.child,
    this.pressedScaleReduction = 0.1,
    this.releaseTension = 1.5,
    super.key,
  });

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Child painted under [Transform.scale].
  final Widget child;

  /// Subtracted from `1.0` while pressed (`.1` actions / `.025` tabs).
  final double pressedScaleReduction;

  /// [OvershootCurve] tension on release (`1.5` actions / `1.2` tabs).
  final double releaseTension;

  /// Press-in duration.
  static const Duration pressDuration = Duration(milliseconds: 80);

  /// Release duration (`defaultAnimator`).
  static const Duration releaseDuration = Duration(milliseconds: 350);

  @override
  State<ScalePressable> createState() => _ScalePressableState();
}

class _ScalePressableState extends State<ScalePressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      value: 1,
      lowerBound: 0.8,
      upperBound: 1.2,
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onPressed == null) return;
    _scale.animateTo(
      1 - widget.pressedScaleReduction,
      duration: ScalePressable.pressDuration,
    );
  }

  void _release() {
    _scale.animateTo(
      1,
      duration: ScalePressable.releaseDuration,
      curve: OvershootCurve(widget.releaseTension),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onPressed == null ? null : (_) => _press(),
      onTapUp: widget.onPressed == null ? null : (_) => _release(),
      onTapCancel: widget.onPressed == null ? null : _release,
      onTap: widget.onPressed,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Overshoot release curve: ends above 1 then settles to 1.
class OvershootCurve extends Curve {
  /// Creates the curve.
  const OvershootCurve(this.tension);

  /// Overshoot amount (higher = more bounce past the end).
  final double tension;

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return u * u * ((tension + 1) * u + tension) + 1;
  }
}
