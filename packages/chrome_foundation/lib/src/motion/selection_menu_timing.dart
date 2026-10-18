/// Timings of the selection menu that are not motion roles: the delays and
/// debounces around its animations, and the size-dependent morph duration.
///
/// They live beside the motion roles because components may not spell a
/// literal `Duration`. Only [dismissDelay] is part of an animation; a host
/// that honours reduce-motion scales it with `ChromeMotionSpeed.scale`. The
/// other two gate when the menu may hide and reappear while the selection
/// moves; they are not animation and stay as they are.
abstract final class SelectionMenuTiming {
  /// How long a dismissing menu waits before it starts to fade out.
  static const Duration dismissDelay = Duration(milliseconds: 150);

  /// How long the menu must have been shown before a moving selection may hide
  /// it; a menu that has just appeared stays put while the selection settles.
  static const Duration movingGrace = Duration(milliseconds: 500);

  /// How long after the last selection move the hidden menu comes back.
  static const Duration settleDebounce = Duration(milliseconds: 50);

  /// The morph diagonal, in logical pixels, under which the overflow morph is
  /// shortened to 0.8 of its role duration.
  static const double shortDiagonal = 150;

  /// The morph diagonal, in logical pixels, over which the overflow morph is
  /// lengthened to 1.2 of its role duration.
  static const double longDiagonal = 300;

  /// The duration of the overflow morph for a card whose size changes along
  /// [diagonal] logical pixels: 0.8 of [base] under [shortDiagonal], 1.2 over
  /// [longDiagonal], [base] between.
  ///
  /// The reference client does this on a 250 ms base (200 / 250 / 300 ms), so
  /// a host that overrides the role keeps the proportions. [base] is the
  /// role's duration, scaled by speed afterwards: an instant speed stays
  /// zero.
  static Duration morphDuration(Duration base, {required double diagonal}) {
    final factor = diagonal < shortDiagonal
        ? 0.8
        : diagonal > longDiagonal
        ? 1.2
        : 1.0;
    return Duration(microseconds: (base.inMicroseconds * factor).round());
  }
}
