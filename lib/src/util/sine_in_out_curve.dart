import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Exact sine ease-in-out, `(1 - cos(πt)) / 2`. [Curves.easeInOutSine] is a
/// cubic approximation of it.
@internal
final class SineInOutCurve extends Curve {
  /// The curve has no parameters; every instance is equal.
  const SineInOutCurve();

  @override
  double transformInternal(double t) => (1 - math.cos(math.pi * t)) / 2;
}
