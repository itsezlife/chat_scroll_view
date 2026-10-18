import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Android's default `ObjectAnimator` easing: `0.5 - cos(pi t) / 2`.
///
/// `Curves.easeInOutSine` is a cubic approximation of the same shape; the
/// selection menu's enter and leave use the exact function so their timing
/// matches the reference client's frame for frame.
class AccelerateDecelerateCurve extends Curve {
  /// The curve.
  const AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => 0.5 - math.cos(math.pi * t) / 2;
}

/// The reference client's `LogAccelerateInterpolator` with base 100:
/// `1 - (1 - 100^-(1 - t)) / 0.99`.
///
/// It starts very slowly and ends fast, which is what lets the overflow
/// morph's width trail its height on open (and lead it on close).
class LogAccelerateCurve extends Curve {
  /// The curve.
  const LogAccelerateCurve();

  static const double _base = 100;

  @override
  double transformInternal(double t) =>
      1 - (1 - math.pow(_base, -(1 - t))) / (1 - 1 / _base);
}
