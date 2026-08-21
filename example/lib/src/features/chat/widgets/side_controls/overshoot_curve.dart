import 'package:flutter/animation.dart';

/// Easing that overshoots past 1.0 then settles (press release, badge appear).
///
/// Apply via [Curve.transform]. [AnimationController] clamps to `[0, 1]`, so
/// passing this as `animateTo(curve:)` alone will not show overshoot.
class OvershootCurve extends Curve {
  /// Creates an [OvershootCurve] with the given tension.
  const OvershootCurve([this.tension = 2.0]);

  /// Overshoot amount. Default `2.0`.
  final double tension;

  @override
  double transformInternal(double t) {
    final x = t - 1.0;
    return x * x * ((tension + 1.0) * x + tension) + 1.0;
  }
}
