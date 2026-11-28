import 'package:chrome_foundation/src/motion/appear_motion.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:flutter/animation.dart';

/// Timing of a surface that grows out of its source on a spring and goes
/// back into it: content scaled up from the source with an action list
/// under it, as an iOS context surface opens from the control that raised
/// it.
///
/// The spring, its cut and the start scale are the context menu's
/// ([AppearMotion$Spring]); the content's own fades are this surface's.
abstract final class ChromeSourceSpringTiming {
  /// The spring the content and the actions scale and move on: overdamped,
  /// so neither passes full size.
  static const SpringDescription spring = AppearMotion$Spring.spring;

  /// Where the open's spring is cut: 0.42 s.
  static const Duration springCut = AppearMotion$Spring.show;

  /// The scale the content and the actions come from and go back to.
  static const double startScale = AppearMotion$Spring.startScale;

  /// The content's fade in on open: 0.15 s on the ease in-out.
  static const MotionSpec contentShowFade = MotionSpec(
    Duration(milliseconds: 150),
    AppearMotion$Spring.ease,
  );

  /// The actions' fade in on open: 0.05 s on the ease in-out.
  static const MotionSpec actionsShowFade = MotionSpec(
    AppearMotion$Spring.showFade,
    AppearMotion$Spring.ease,
  );

  /// The close: scale and position back toward the source, 0.2 s ease
  /// in-out.
  static const MotionSpec close = MotionSpec(
    AppearMotion$Spring.hide,
    AppearMotion$Spring.ease,
  );

  /// The content's fade out on close: 0.16 s on the ease in-out, so it is
  /// gone just before the close ends.
  static const MotionSpec contentHideFade = MotionSpec(
    Duration(milliseconds: 160),
    AppearMotion$Spring.ease,
  );

  /// The content's height following a change of what it shows: 0.5 s ease
  /// in-out (the source's update; its curve is unverified).
  static const MotionSpec change = MotionSpec(
    Duration(milliseconds: 500),
    Curves.easeInOut,
  );
}
