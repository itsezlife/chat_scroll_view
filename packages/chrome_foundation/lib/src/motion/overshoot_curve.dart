import 'package:flutter/animation.dart';

/// Release settle that passes the end value, then returns to it.
///
/// Formula: `u²·((tension+1)·u + tension) + 1` with `u = t − 1`. It is
/// Android's `OvershootInterpolator`: `0` at `0`, `1` at `1`, above `1` in
/// between for a positive [tension].
///
/// An `AnimationController` clamps its value to `[0, 1]`, so a controller with
/// default bounds shows no overshoot through `animateTo(curve:)` alone. Drive
/// a controller whose bounds reach past `1` (as `ScalePressable` does), or
/// call [transform] yourself.
class OvershootCurve extends Curve {
  /// Creates a curve with the given [tension]; higher means more bounce.
  ///
  /// The default, `2`, is Android's.
  const OvershootCurve([this.tension = 2.0]);

  /// How far past the end value the curve travels before settling.
  final double tension;

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return u * u * ((tension + 1) * u + tension) + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is OvershootCurve && other.tension == tension;

  @override
  int get hashCode => tension.hashCode;

  @override
  String toString() => 'OvershootCurve($tension)';
}
