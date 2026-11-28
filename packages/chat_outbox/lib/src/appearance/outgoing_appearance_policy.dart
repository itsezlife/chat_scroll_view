import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// How a fresh outgoing row appears, as a name: what the host animates and
/// what the `rowAppeared` event reports.
enum OutgoingAppearanceForm {
  /// The rows translate up from below by the added row's height.
  slideUp,

  /// The bubble fades in and grows to its size around its centre.
  fadeScale,

  /// The row stays still: the media cells fly in from the send origin.
  flight,

  /// The row is there at once.
  none,
}

/// How a policy moves a fresh row of its own: the forms of
/// [OutgoingAppearanceForm] but the flight, which comes from a send origin
/// only ([OutgoingAppearancePolicy.fliesFromOrigin]).
enum OutgoingRowMotion {
  /// The rows translate up from below by the added row's height.
  slideUp,

  /// The bubble fades in and grows to its size around its centre.
  fadeScale,

  /// The row is there at once.
  none,
}

/// The values a fresh outgoing row appears with on each platform, and the
/// resolver from the row's situation to the [OutgoingAppearance] the host
/// animates.
///
/// | | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | at the bottom | [OutgoingAppearanceForm.slideUp]: 250 ms on `(0.199, 0.011, 0.279, 0.910)`, the rows at full opacity | the media flies from its send origin; without one, as Android | none |
/// | off the bottom | [OutgoingAppearanceForm.fadeScale]: opacity 0 → 1 and scale 0.9 → 1 around the bubble centre, 250 ms, after up to 100 ms ([OutgoingAppearance$FadeScale.delayAt]) | the same flight; without an origin, as Android | none |
/// | a text-only message | as media, never a flight | as media, never a flight | none |
///
/// The web is not the desktop: a page takes its form from its window and
/// its input, live, not from the system it runs on ([web]).
///
/// The whole-row motion is the host's, since it owns the row: it asks the
/// outbox's `appearanceOf` (or `isFreshOutgoing` and [resolve] itself) once
/// per row and animates the answer. The flight is the media cells' own;
/// this policy only says the row then stays still. The platform's reduce
/// motion switch collapses every form to [OutgoingAppearanceForm.none].
///
/// Pure values: no widget reads it, so a host with its own row animations
/// keeps the numbers and the decision.
@immutable
final class OutgoingAppearancePolicy {
  /// A policy of the given forms; the motions' values default to
  /// Android's.
  const OutgoingAppearancePolicy({
    required this.atBottom,
    required this.offBottom,
    required this.fliesFromOrigin,
    this.slideDuration = const Duration(milliseconds: 250),
    this.slideCurve = listItemCurve,
    this.fadeScaleDuration = const Duration(milliseconds: 250),
    this.fadeScaleCurve = Curves.easeInOutSine,
    this.opacityFrom = 0,
    this.scaleFrom = 0.9,
    this.maxStartDelay = const Duration(milliseconds: 100),
  });

  /// Android: the rows slide up at the bottom, the bubble fades and scales
  /// in elsewhere; a send origin is ignored.
  const OutgoingAppearancePolicy.android()
    : this(
        atBottom: OutgoingRowMotion.slideUp,
        offBottom: OutgoingRowMotion.fadeScale,
        fliesFromOrigin: false,
      );

  /// iOS: media with a send origin flies in and the row stays still;
  /// anything else appears as on Android.
  const OutgoingAppearancePolicy.ios()
    : this(
        atBottom: OutgoingRowMotion.slideUp,
        offBottom: OutgoingRowMotion.fadeScale,
        fliesFromOrigin: true,
      );

  /// Desktop: a sent row is there at once.
  const OutgoingAppearancePolicy.desktop()
    : this(
        atBottom: OutgoingRowMotion.none,
        offBottom: OutgoingRowMotion.none,
        fliesFromOrigin: false,
      );

  /// The web, by its window and its input as they are now: a compact
  /// window used by touch ([compactTouch], the host's reading of the width
  /// class and the input class) moves as a phone, Android's values; any
  /// other window is there at once, as the desktop. A page never flies
  /// media in, whichever system's browser it runs in.
  ///
  /// Both classes are live (a window resized, a mouse picked up), so the
  /// host reads them as each fresh row appears and hands the result to
  /// `ChatOutbox.appearanceOf`.
  factory OutgoingAppearancePolicy.web({required bool compactTouch}) =>
      compactTouch
      ? const OutgoingAppearancePolicy.android()
      : const OutgoingAppearancePolicy.desktop();

  /// The preset of [platform], the running one's by default: Android's for
  /// Android and Fuchsia, iOS's for iOS, desktop's for macOS, Windows and
  /// Linux. On the web ([isWeb], the running build's by default) the
  /// system does not decide: [web] for a window that is not a compact one
  /// used by touch, until the host passes the live one.
  factory OutgoingAppearancePolicy.platform({
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    if (isWeb) return OutgoingAppearancePolicy.web(compactTouch: false);
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia => const OutgoingAppearancePolicy.android(),
      TargetPlatform.iOS => const OutgoingAppearancePolicy.ios(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const OutgoingAppearancePolicy.desktop(),
    };
  }

  /// The curve a list item moves on: the rows' slide.
  static const Cubic listItemCurve = Cubic(0.199, 0.011, 0.279, 0.910);

  /// How a row appears while the list is at its bottom (the newest message
  /// in view).
  final OutgoingRowMotion atBottom;

  /// How a row appears while the list is scrolled up into history.
  final OutgoingRowMotion offBottom;

  /// Whether media with a send origin flies in from it, the row staying
  /// still; without an origin, and for a text-only message, [atBottom] or
  /// [offBottom] applies.
  final bool fliesFromOrigin;

  /// How long the rows take to slide up.
  final Duration slideDuration;

  /// The curve the rows slide up on.
  final Curve slideCurve;

  /// How long the bubble takes to fade and scale in, after its delay.
  final Duration fadeScaleDuration;

  /// The curve the bubble fades and scales in on: the platform's default
  /// accelerate-then-decelerate.
  final Curve fadeScaleCurve;

  /// The bubble's opacity as it starts to fade in.
  final double opacityFrom;

  /// The bubble's scale as it starts to grow, around its centre.
  final double scaleFrom;

  /// The longest wait before the bubble fades in: a row at the list's top
  /// waits all of it, one at the bottom none.
  final Duration maxStartDelay;

  /// How a fresh outgoing row appears: with the list at its bottom
  /// ([atBottom]) or not, a send origin held for one of its items
  /// ([originPresent]), no media at all ([textOnly]), and the platform's
  /// reduce motion switch ([reduceMotion]), which wins over everything.
  OutgoingAppearance resolve({
    required bool atBottom,
    required bool originPresent,
    required bool textOnly,
    required bool reduceMotion,
  }) {
    if (reduceMotion) return const OutgoingAppearance.none();
    if (fliesFromOrigin && originPresent && !textOnly) {
      return const OutgoingAppearance.flight();
    }
    return switch (atBottom ? this.atBottom : offBottom) {
      OutgoingRowMotion.slideUp => OutgoingAppearance.slideUp(
        duration: slideDuration,
        curve: slideCurve,
      ),
      OutgoingRowMotion.fadeScale => OutgoingAppearance.fadeScale(
        duration: fadeScaleDuration,
        curve: fadeScaleCurve,
        opacityFrom: opacityFrom,
        scaleFrom: scaleFrom,
        maxStartDelay: maxStartDelay,
      ),
      OutgoingRowMotion.none => const OutgoingAppearance.none(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is OutgoingAppearancePolicy &&
      other.atBottom == atBottom &&
      other.offBottom == offBottom &&
      other.fliesFromOrigin == fliesFromOrigin &&
      other.slideDuration == slideDuration &&
      other.slideCurve == slideCurve &&
      other.fadeScaleDuration == fadeScaleDuration &&
      other.fadeScaleCurve == fadeScaleCurve &&
      other.opacityFrom == opacityFrom &&
      other.scaleFrom == scaleFrom &&
      other.maxStartDelay == maxStartDelay;

  @override
  int get hashCode => Object.hash(
    atBottom,
    offBottom,
    fliesFromOrigin,
    slideDuration,
    slideCurve,
    fadeScaleDuration,
    fadeScaleCurve,
    opacityFrom,
    scaleFrom,
    maxStartDelay,
  );
}

/// How one fresh outgoing row appears: what [OutgoingAppearancePolicy.resolve]
/// answered, carrying the values its form animates with.
@immutable
sealed class OutgoingAppearance {
  const OutgoingAppearance._();

  /// The rows slide up by the added row's height.
  const factory OutgoingAppearance.slideUp({
    required Duration duration,
    required Curve curve,
  }) = OutgoingAppearance$SlideUp;

  /// The bubble fades and scales in, after a delay by its place.
  const factory OutgoingAppearance.fadeScale({
    required Duration duration,
    required Curve curve,
    required double opacityFrom,
    required double scaleFrom,
    required Duration maxStartDelay,
  }) = OutgoingAppearance$FadeScale;

  /// The row stays still while its media flies in.
  const factory OutgoingAppearance.flight() = OutgoingAppearance$Flight;

  /// The row is there at once.
  const factory OutgoingAppearance.none() = OutgoingAppearance$None;

  /// This appearance's form, as the `rowAppeared` event names it.
  OutgoingAppearanceForm get form;
}

/// [OutgoingAppearance.slideUp].
final class OutgoingAppearance$SlideUp extends OutgoingAppearance {
  /// A slide of [duration] on [curve].
  const OutgoingAppearance$SlideUp({
    required this.duration,
    required this.curve,
  }) : super._();

  /// How long the rows take to slide up.
  final Duration duration;

  /// The curve they slide on.
  final Curve curve;

  @override
  OutgoingAppearanceForm get form => OutgoingAppearanceForm.slideUp;

  @override
  bool operator ==(Object other) =>
      other is OutgoingAppearance$SlideUp &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(OutgoingAppearance$SlideUp, duration, curve);
}

/// [OutgoingAppearance.fadeScale].
final class OutgoingAppearance$FadeScale extends OutgoingAppearance {
  /// A fade from [opacityFrom] and a scale from [scaleFrom], of [duration]
  /// on [curve], after at most [maxStartDelay].
  const OutgoingAppearance$FadeScale({
    required this.duration,
    required this.curve,
    required this.opacityFrom,
    required this.scaleFrom,
    required this.maxStartDelay,
  }) : super._();

  /// How long the bubble takes to fade and scale in.
  final Duration duration;

  /// The curve it fades and scales on.
  final Curve curve;

  /// Its opacity at the start.
  final double opacityFrom;

  /// Its scale at the start, around its centre.
  final double scaleFrom;

  /// The longest wait before it starts.
  final Duration maxStartDelay;

  /// The wait before the bubble starts, by where its row ends: a row whose
  /// bottom is [rowBottom] in a list [listHeight] tall waits
  /// `(1 − rowBottom / listHeight) · maxStartDelay`, so rows near the
  /// bottom, where the eye is, come first. The fraction is clamped to the
  /// list; a list of no height waits nothing.
  Duration delayAt({required double rowBottom, required double listHeight}) {
    if (listHeight <= 0) return Duration.zero;
    final fraction = (rowBottom / listHeight).clamp(0.0, 1.0);
    return Duration(
      microseconds: ((1 - fraction) * maxStartDelay.inMicroseconds).round(),
    );
  }

  @override
  OutgoingAppearanceForm get form => OutgoingAppearanceForm.fadeScale;

  @override
  bool operator ==(Object other) =>
      other is OutgoingAppearance$FadeScale &&
      other.duration == duration &&
      other.curve == curve &&
      other.opacityFrom == opacityFrom &&
      other.scaleFrom == scaleFrom &&
      other.maxStartDelay == maxStartDelay;

  @override
  int get hashCode => Object.hash(
    OutgoingAppearance$FadeScale,
    duration,
    curve,
    opacityFrom,
    scaleFrom,
    maxStartDelay,
  );
}

/// [OutgoingAppearance.flight].
final class OutgoingAppearance$Flight extends OutgoingAppearance {
  /// The flight.
  const OutgoingAppearance$Flight() : super._();

  @override
  OutgoingAppearanceForm get form => OutgoingAppearanceForm.flight;

  @override
  bool operator ==(Object other) => other is OutgoingAppearance$Flight;

  @override
  int get hashCode => (OutgoingAppearance$Flight).hashCode;
}

/// [OutgoingAppearance.none].
final class OutgoingAppearance$None extends OutgoingAppearance {
  /// No appearance.
  const OutgoingAppearance$None() : super._();

  @override
  OutgoingAppearanceForm get form => OutgoingAppearanceForm.none;

  @override
  bool operator ==(Object other) => other is OutgoingAppearance$None;

  @override
  int get hashCode => (OutgoingAppearance$None).hashCode;
}
