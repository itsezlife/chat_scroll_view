import 'package:chrome_foundation/src/motion/overshoot_curve.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// How a pressed [ChromeInk] target scales about its centre: a value the
/// caller picks, with named presets, not a theme token.
///
/// Two shapes: [ChromeInkBounce] (a fixed factor, an overshoot on release)
/// and [ChromeInkInset] (a factor derived from the laid-out width). A press
/// that ends by moving off the target or by a scroll or drag taking the
/// pointer returns as a release does, overshoot included. An instant motion
/// speed (reduce motion) removes the scale.
@immutable
sealed class ChromeInkScale {
  const ChromeInkScale({
    required this.pressDuration,
    required this.pressCurve,
    required this.releaseDuration,
    required this.releaseCurve,
  });

  /// How long the scale takes to reach its pressed value.
  final Duration pressDuration;

  /// The curve of that scale.
  final Curve pressCurve;

  /// How long the scale takes to come back to 1.
  final Duration releaseDuration;

  /// The curve of the return.
  final Curve releaseCurve;

  /// The scale of a target [width] logical pixels wide while pressed.
  double pressedScale(double width);
}

/// A press that scales the target to a fixed [factor] and releases it with an
/// overshoot.
final class ChromeInkBounce extends ChromeInkScale {
  /// A bounce to [factor] over [pressDuration] and back over
  /// [releaseDuration] on [releaseCurve].
  const ChromeInkBounce({
    required this.factor,
    super.pressDuration = const Duration(milliseconds: 120),
    super.pressCurve = const Cubic(0.25, 0.1, 0.25, 1),
    super.releaseDuration = const Duration(milliseconds: 700),
    super.releaseCurve = const OvershootCurve(),
  });

  /// A large target (a card): to 0.99, 120 ms in, 700 ms out with an overshoot
  /// of 2.
  static const ChromeInkBounce card = ChromeInkBounce(factor: 0.99);

  /// A small target (a button): to 0.98, 60 ms in, 350 ms out with an
  /// overshoot of 5.
  static const ChromeInkBounce button = ChromeInkBounce(
    factor: 0.98,
    pressDuration: Duration(milliseconds: 60),
    releaseDuration: Duration(milliseconds: 350),
    releaseCurve: OvershootCurve(5),
  );

  /// The scale while pressed.
  final double factor;

  @override
  double pressedScale(double width) => factor;

  @override
  bool operator ==(Object other) =>
      other is ChromeInkBounce &&
      other.factor == factor &&
      other.pressDuration == pressDuration &&
      other.pressCurve == pressCurve &&
      other.releaseDuration == releaseDuration &&
      other.releaseCurve == releaseCurve;

  @override
  int get hashCode => Object.hash(
    factor,
    pressDuration,
    pressCurve,
    releaseDuration,
    releaseCurve,
  );
}

/// A press that shrinks the target by [inset] logical pixels of its width:
/// to `(w - inset) / w`, from the laid-out width.
final class ChromeInkInset extends ChromeInkScale {
  /// An inset scale of [inset] over [pressDuration] and back over
  /// [releaseDuration], both on [pressCurve] and [releaseCurve].
  const ChromeInkInset({
    required this.inset,
    super.pressDuration = const Duration(milliseconds: 300),
    super.pressCurve = Curves.easeInOut,
    super.releaseDuration = const Duration(milliseconds: 200),
    super.releaseCurve = Curves.easeInOut,
  });

  /// A large target (a card): 5 logical pixels, 0.3 s in, 0.2 s out.
  static const ChromeInkInset card = ChromeInkInset(inset: 5);

  /// A small target (a button): 10 logical pixels, 0.15 s in, 0.25 s out.
  static const ChromeInkInset button = ChromeInkInset(
    inset: 10,
    pressDuration: Duration(milliseconds: 150),
    releaseDuration: Duration(milliseconds: 250),
  );

  /// How much of the width the press takes off.
  final double inset;

  @override
  double pressedScale(double width) =>
      width <= inset ? 1 : (width - inset) / width;

  @override
  bool operator ==(Object other) =>
      other is ChromeInkInset &&
      other.inset == inset &&
      other.pressDuration == pressDuration &&
      other.pressCurve == pressCurve &&
      other.releaseDuration == releaseDuration &&
      other.releaseCurve == releaseCurve;

  @override
  int get hashCode => Object.hash(
    inset,
    pressDuration,
    pressCurve,
    releaseDuration,
    releaseCurve,
  );
}
