import 'dart:math' as math;

import 'package:chrome_foundation/src/menu/pointer_menu_reveal.dart';
import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/motion/overshoot_curve.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The **appear motion**: how a menu or an overlay comes up and goes, one
/// motion per platform family, so every menu, popup and preview of a platform
/// moves alike.
///
/// A surface asks for [forPlatform] (or names a variant), and a
/// `ChromeAppear` plays it. The motion is described per moment as an
/// [AppearFrame]: what part of the surface shows and how it is drawn, relative
/// to an origin (the corner or edge the surface is anchored at).
///
/// - [AppearMotion.grow]: the desktop panel. The surface is drawn at its
///   final size inside a frame that grows from the origin corner, from half
///   its width and 30% of its height, fading in, while a strip uncovers its
///   content from the top (`PointerMenuReveal`); the open and close take the
///   pointer menu's roles. It goes by a linear fade at full size.
/// - [AppearMotion.unfold]: the Android popup. The surface opens its height
///   from the anchored edge and fades in, both accelerating then
///   decelerating, over 150 ms and 16 more for each row; it goes over 150 ms,
///   drifting 5 toward its anchor as it fades.
/// - [AppearMotion.spring]: the iOS context menu. The surface scales up from
///   0.01 about its origin on an overdamped spring (stiffness 900, damping
///   104, mass 1) cut at 420 ms, opaque after its first 50 ms; it goes over
///   200 ms, shrinking back to 0.01 as it fades, easing in and out.
///
/// Two Android variants belong to the message menu, which a host names:
///
/// - [AppearMotion.bloom]: the menu that comes with a reaction strip. Its
///   frame opens from the origin corner while its content (an
///   `AppearContent`) fades in and scales up from half about that corner, all
///   on one overshooting clock (tension 0.5) over 250 ms; it goes over
///   220 ms, drifting 5 toward its anchor as it fades, accelerating then
///   decelerating.
/// - [AppearMotion.pop]: the menu without one. It fades in over 150 ms,
///   accelerating then decelerating, while it scales up from 0.95 about its
///   origin on an overshoot (tension 2) over 200 ms; it goes as the bloom
///   does.
///
/// The rows of an unfolding menu do not fade in one by one: the whole surface
/// fades with its frame.
@immutable
sealed class AppearMotion {
  const AppearMotion._();

  /// The desktop panel's grow from a corner.
  const factory AppearMotion.grow() = AppearMotion$Grow;

  /// The Android popup's unfold from its anchored edge.
  const factory AppearMotion.unfold() = AppearMotion$Unfold;

  /// The iOS context menu's spring from its origin.
  const factory AppearMotion.spring() = AppearMotion$Spring;

  /// The Android message menu's bloom from its corner, with a reaction strip.
  const factory AppearMotion.bloom() = AppearMotion$Bloom;

  /// The Android message menu's pop, without a reaction strip.
  const factory AppearMotion.pop() = AppearMotion$Pop;

  /// The motion of [platform]'s family: [grow] on a desktop, [spring] on iOS,
  /// [unfold] elsewhere.
  factory AppearMotion.forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => const AppearMotion.grow(),
        TargetPlatform.iOS => const AppearMotion.spring(),
        TargetPlatform.android ||
        TargetPlatform.fuchsia => const AppearMotion.unfold(),
      };

  /// How long the show takes under [motion]'s speed, for a surface of [rows]
  /// rows (only the unfold counts them).
  Duration showDuration(ChromeMotionData motion, {int rows = 0});

  /// How long the hide takes under [motion]'s speed.
  Duration hideDuration(ChromeMotionData motion);

  /// The frame at [t] of the show, 0 at its start and 1 at its end.
  AppearFrame showAt(double t);

  /// The frame at [t] of the hide, 0 at its start and 1 at its end.
  AppearFrame hideAt(double t);
}

/// [AppearMotion.grow].
final class AppearMotion$Grow extends AppearMotion {
  /// The grow.
  const AppearMotion$Grow() : super._();

  @override
  Duration showDuration(ChromeMotionData motion, {int rows = 0}) =>
      motion.durationOf(MotionRole.pointerMenuShow);

  @override
  Duration hideDuration(ChromeMotionData motion) =>
      motion.durationOf(MotionRole.pointerMenuHide);

  @override
  AppearFrame showAt(double t) {
    if (t >= 1) return AppearFrame.rest;
    final reveal = PointerMenuReveal.at(t);
    return AppearFrame(
      opacity: reveal.opacity,
      widthFraction: reveal.widthFraction,
      heightFraction: reveal.heightFraction,
      revealed: reveal.contentRevealed,
    );
  }

  @override
  AppearFrame hideAt(double t) => AppearFrame(opacity: 1 - t.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) => other is AppearMotion$Grow;

  @override
  int get hashCode => (AppearMotion$Grow).hashCode;
}

/// [AppearMotion.unfold].
final class AppearMotion$Unfold extends AppearMotion {
  /// The unfold.
  const AppearMotion$Unfold() : super._();

  /// The show of a surface with no row.
  static const Duration showBase = Duration(milliseconds: 150);

  /// What each row adds to the show.
  static const Duration showPerRow = Duration(milliseconds: 16);

  /// The hide.
  static const Duration hide = Duration(milliseconds: 150);

  /// How far the surface drifts toward its anchor as it goes.
  static const double hideDrift = 5;

  @override
  Duration showDuration(ChromeMotionData motion, {int rows = 0}) =>
      motion.speed.scale(showBase + showPerRow * math.max(0, rows));

  @override
  Duration hideDuration(ChromeMotionData motion) => motion.speed.scale(hide);

  @override
  AppearFrame showAt(double t) {
    if (t >= 1) return AppearFrame.rest;
    final eased = AccelerateDecelerateCurve.instance.transform(
      t.clamp(0.0, 1.0),
    );
    return AppearFrame(opacity: eased, heightFraction: eased);
  }

  @override
  AppearFrame hideAt(double t) {
    final eased = AccelerateDecelerateCurve.instance.transform(
      t.clamp(0.0, 1.0),
    );
    return AppearFrame(opacity: 1 - eased, drift: hideDrift * eased);
  }

  @override
  bool operator ==(Object other) => other is AppearMotion$Unfold;

  @override
  int get hashCode => (AppearMotion$Unfold).hashCode;
}

/// [AppearMotion.spring].
final class AppearMotion$Spring extends AppearMotion {
  /// The spring.
  const AppearMotion$Spring() : super._();

  /// The show: where the spring is cut.
  static const Duration show = Duration(milliseconds: 420);

  /// How long the fade in of the show takes.
  static const Duration showFade = Duration(milliseconds: 50);

  /// The hide.
  static const Duration hide = Duration(milliseconds: 200);

  /// The scale the surface comes from and goes back to.
  static const double startScale = 0.01;

  /// The spring the show scales on: overdamped, so it never passes full size.
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 900,
    damping: 104,
  );

  /// The ease of the show's fade and of the hide.
  static const Curve ease = Cubic(0.42, 0, 0.58, 1);

  static final SpringSimulation _simulation = SpringSimulation(spring, 0, 1, 0);

  @override
  Duration showDuration(ChromeMotionData motion, {int rows = 0}) =>
      motion.speed.scale(show);

  @override
  Duration hideDuration(ChromeMotionData motion) => motion.speed.scale(hide);

  @override
  AppearFrame showAt(double t) {
    if (t >= 1) return AppearFrame.rest;
    final clock = t.clamp(0.0, 1.0);
    final seconds =
        clock * show.inMicroseconds / Duration.microsecondsPerSecond;
    final grown = _simulation.x(seconds);
    final fade = (clock * show.inMicroseconds / showFade.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    return AppearFrame(
      opacity: ease.transform(fade),
      scale: startScale + (1 - startScale) * grown,
    );
  }

  @override
  AppearFrame hideAt(double t) {
    final eased = ease.transform(t.clamp(0.0, 1.0));
    return AppearFrame(opacity: 1 - eased, scale: 1 - (1 - startScale) * eased);
  }

  @override
  bool operator ==(Object other) => other is AppearMotion$Spring;

  @override
  int get hashCode => (AppearMotion$Spring).hashCode;
}

/// The hide the message menu variants share: 220 ms, drifting toward the
/// anchor as the surface fades, accelerating then decelerating.
abstract final class _MessageMenuHide {
  static const Duration duration = Duration(milliseconds: 220);

  static const double drift = 5;

  static AppearFrame at(double t) {
    final eased = AccelerateDecelerateCurve.instance.transform(
      t.clamp(0.0, 1.0),
    );
    return AppearFrame(opacity: 1 - eased, drift: drift * eased);
  }
}

/// [AppearMotion.bloom].
final class AppearMotion$Bloom extends AppearMotion {
  /// The bloom.
  const AppearMotion$Bloom() : super._();

  /// The show.
  static const Duration show = Duration(milliseconds: 250);

  /// The overshoot the show runs on.
  static const Curve curve = OvershootCurve(0.5);

  /// The scale the content comes from.
  static const double contentStartScale = 0.5;

  /// The hide.
  static const Duration hide = _MessageMenuHide.duration;

  /// How far the surface drifts toward its anchor as it goes.
  static const double hideDrift = _MessageMenuHide.drift;

  @override
  Duration showDuration(ChromeMotionData motion, {int rows = 0}) =>
      motion.speed.scale(show);

  @override
  Duration hideDuration(ChromeMotionData motion) => motion.speed.scale(hide);

  @override
  AppearFrame showAt(double t) {
    if (t >= 1) return AppearFrame.rest;
    final p = curve.transform(t.clamp(0.0, 1.0));
    return AppearFrame(
      widthFraction: p,
      heightFraction: p,
      contentOpacity: p.clamp(0.0, 1.0),
      contentScale: contentStartScale + (1 - contentStartScale) * p,
    );
  }

  @override
  AppearFrame hideAt(double t) => _MessageMenuHide.at(t);

  @override
  bool operator ==(Object other) => other is AppearMotion$Bloom;

  @override
  int get hashCode => (AppearMotion$Bloom).hashCode;
}

/// [AppearMotion.pop].
final class AppearMotion$Pop extends AppearMotion {
  /// The pop.
  const AppearMotion$Pop() : super._();

  /// The show: the scale's length.
  static const Duration show = Duration(milliseconds: 200);

  /// How long the fade in takes.
  static const Duration showFade = Duration(milliseconds: 150);

  /// The overshoot the scale runs on.
  static const Curve scaleCurve = OvershootCurve();

  /// The scale the surface comes from.
  static const double startScale = 0.95;

  /// The hide.
  static const Duration hide = _MessageMenuHide.duration;

  /// How far the surface drifts toward its anchor as it goes.
  static const double hideDrift = _MessageMenuHide.drift;

  @override
  Duration showDuration(ChromeMotionData motion, {int rows = 0}) =>
      motion.speed.scale(show);

  @override
  Duration hideDuration(ChromeMotionData motion) => motion.speed.scale(hide);

  @override
  AppearFrame showAt(double t) {
    if (t >= 1) return AppearFrame.rest;
    final clock = t.clamp(0.0, 1.0);
    final fade = (clock * show.inMicroseconds / showFade.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    return AppearFrame(
      opacity: AccelerateDecelerateCurve.instance.transform(fade),
      scale: startScale + (1 - startScale) * scaleCurve.transform(clock),
    );
  }

  @override
  AppearFrame hideAt(double t) => _MessageMenuHide.at(t);

  @override
  bool operator ==(Object other) => other is AppearMotion$Pop;

  @override
  int get hashCode => (AppearMotion$Pop).hashCode;
}

/// `cos((t + 1)·π) / 2 + 0.5`: starts and ends slowly, Android's default
/// interpolator.
class AccelerateDecelerateCurve extends Curve {
  /// The curve.
  const AccelerateDecelerateCurve();

  /// The one instance.
  static const AccelerateDecelerateCurve instance = AccelerateDecelerateCurve();

  @override
  double transformInternal(double t) => math.cos((t + 1) * math.pi) / 2 + 0.5;
}

/// One moment of an [AppearMotion], relative to the surface's origin.
@immutable
final class AppearFrame {
  /// A frame; the defaults are the surface at rest.
  const AppearFrame({
    this.opacity = 1,
    this.scale = 1,
    this.widthFraction = 1,
    this.heightFraction = 1,
    this.drift = 0,
    this.revealed = 1,
    this.contentOpacity = 1,
    this.contentScale = 1,
  });

  /// A [show] frame with a [hide] frame over it: what a surface draws when
  /// its hide starts before its show is over, or a show turns a hide back.
  ///
  /// The geometry is the show's (frame, strip, content), the hide's drift
  /// added; opacities and scales multiply. A hide over a finished show is
  /// the hide's frame, a show under no hide is the show's.
  factory AppearFrame.compose({
    required AppearFrame show,
    required AppearFrame hide,
  }) => AppearFrame(
    opacity: show.opacity * hide.opacity,
    scale: show.scale * hide.scale,
    widthFraction: show.widthFraction * hide.widthFraction,
    heightFraction: show.heightFraction * hide.heightFraction,
    drift: show.drift + hide.drift,
    revealed: show.revealed * hide.revealed,
    contentOpacity: show.contentOpacity * hide.contentOpacity,
    contentScale: show.contentScale * hide.contentScale,
  );

  /// The surface at rest: whole, opaque, in place.
  static const AppearFrame rest = AppearFrame();

  /// The opacity of the whole surface.
  final double opacity;

  /// The scale of the surface about its origin.
  final double scale;

  /// The width of the frame the surface shows through, as a fraction of its
  /// own, held at the origin.
  final double widthFraction;

  /// The height of that frame, as a fraction of the surface's own.
  final double heightFraction;

  /// How far the surface has moved toward its origin's edge, in logical
  /// pixels.
  final double drift;

  /// How far a strip has swept down the frame, uncovering the content from
  /// the top: 0 hides it all, 1 shows it all.
  final double revealed;

  /// The opacity of the surface's content (what an `AppearContent` wraps),
  /// over its background.
  final double contentOpacity;

  /// The scale of the surface's content about the origin, inside its
  /// background.
  final double contentScale;

  /// Whether the frame cuts the surface.
  bool get clips => widthFraction < 1 || heightFraction < 1;

  /// The frame inside a surface of [size], held at [origin].
  Rect frameIn(Size size, Alignment origin) {
    final width = size.width * widthFraction;
    final height = size.height * heightFraction;
    return Rect.fromLTWH(
      (size.width - width) * (origin.x + 1) / 2,
      (size.height - height) * (origin.y + 1) / 2,
      width,
      height,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearFrame &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.widthFraction == widthFraction &&
      other.heightFraction == heightFraction &&
      other.drift == drift &&
      other.revealed == revealed &&
      other.contentOpacity == contentOpacity &&
      other.contentScale == contentScale;

  @override
  int get hashCode => Object.hash(
    opacity,
    scale,
    widthFraction,
    heightFraction,
    drift,
    revealed,
    contentOpacity,
    contentScale,
  );

  @override
  String toString() =>
      'AppearFrame(opacity: $opacity, scale: $scale, '
      'frame: ${widthFraction}x$heightFraction, drift: $drift, '
      'revealed: $revealed, content: $contentOpacity x$contentScale)';
}
