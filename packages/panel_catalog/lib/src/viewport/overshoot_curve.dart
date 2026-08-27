import 'package:flutter/animation.dart';

/// Release settle that overshoots past the end then returns.
///
/// Formula: `u²·((tension+1)·u + tension) + 1` where `u = t − 1`.
/// Tension `5` is the catalog leaf press-out default.
class OvershootCurve extends Curve {
  /// Creates a curve with the given [tension] (higher = more bounce).
  const OvershootCurve(this.tension);

  /// Overshoot amount past the target before settling.
  final double tension;

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return u * u * ((tension + 1) * u + tension) + 1;
  }
}
