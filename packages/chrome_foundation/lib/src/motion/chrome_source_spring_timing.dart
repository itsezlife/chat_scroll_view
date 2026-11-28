import 'package:chrome_foundation/src/motion/appear_motion.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:flutter/animation.dart';

/// Timing of a surface that grows out of its source on a spring and goes
/// back into it: content scaled up from the source with an action list
/// under it, as a context surface opens from the control that raised it.
///
/// The spring, its cut, the start scale, the actions' fade and the close
/// are the context menu's, taken from [AppearMotion$Spring]; these are the
/// content's own fades and its change.
abstract final class ChromeSourceSpringTiming {
  /// The content's fade in on open: 0.15 s on the ease in-out.
  static const MotionSpec contentShowFade = MotionSpec(
    Duration(milliseconds: 150),
    AppearMotion$Spring.ease,
  );

  /// The content's fade out on close: 0.16 s on the ease in-out, so it is
  /// gone just before the close ends.
  static const MotionSpec contentHideFade = MotionSpec(
    Duration(milliseconds: 160),
    AppearMotion$Spring.ease,
  );

  /// The content's height following a change of what it shows: 0.5 s ease
  /// in-out.
  static const MotionSpec change = MotionSpec(
    Duration(milliseconds: 500),
    Curves.easeInOut,
  );
}
