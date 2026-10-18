import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// `easeOutCirc`: `sqrt(1 - (t - 1)^2)`, the curve the reference desktop
/// client's popup panel grows on (`anim::easeOutCirc`).
///
/// Flutter's `Curves` has no circular ease-out; a pointer menu's width, height
/// and opacity each run on this curve over a fraction of one shared clock
/// (see `PointerMenuReveal`).
class EaseOutCirc extends Curve {
  /// The curve.
  const EaseOutCirc();

  @override
  double transformInternal(double t) => math.sqrt(1 - (t - 1) * (t - 1));
}

/// Timings of the pointer menu that are not role durations.
///
/// The open and close fades are the `pointerMenuShow` and `pointerMenuHide`
/// roles of [ChromeMotion], so reduce-motion reaches them. These three are a
/// hold and a ripple, not menu motion: a speed multiplier would only make a
/// submenu harder to reach, so they stay literal and live with the other
/// literal durations in this directory.
abstract final class PointerMenuTiming {
  /// How long a submenu holds the highlighted row while the pointer travels
  /// toward it, after the pointer last moved inside the aim triangle
  /// (`kSubmenuAimDelay`, 300 ms).
  static const Duration aimHold = Duration(milliseconds: 300);

  /// How long a press ripple grows, on `easeOutQuint` (the style's
  /// `ripple.showDuration`, 650 ms).
  static const Duration rippleGrow = Duration(milliseconds: 650);

  /// How long a ripple takes to fade once the press ends (the style's
  /// `ripple.hideDuration`, 200 ms).
  static const Duration rippleFade = Duration(milliseconds: 200);
}
