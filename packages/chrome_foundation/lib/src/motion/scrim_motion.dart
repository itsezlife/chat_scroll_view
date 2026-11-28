import 'package:chrome_foundation/src/motion/appear_motion.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:chrome_foundation/src/motion/pointer_menu_motion.dart';
import 'package:flutter/animation.dart';

/// The fades of the chrome scrim's presets (`ChromeScrimPreset`).
///
/// They are not `ChromeMotion` roles: each belongs to one platform's scrim
/// and is picked by its preset; a host tunes one by copying the preset with
/// another spec. They live in this directory with the other literal
/// durations.
abstract final class ScrimMotion {
  /// The Android overlay's scrim. The overlay sets no duration of its own,
  /// so this is the platform's default property animation: 300 ms
  /// accelerate-decelerate (unverified on a device).
  static const MotionSpec android = MotionSpec(
    Duration(milliseconds: 300),
    AccelerateDecelerateCurve.instance,
  );

  /// The iOS and iPad backdrop: 0.2 s ease-in-out.
  static const MotionSpec ios = MotionSpec(
    Duration(milliseconds: 200),
    Curves.easeInOut,
  );

  /// The desktop box's background: 200 ms ease-out-circ.
  static const MotionSpec desktop = MotionSpec(
    Duration(milliseconds: 200),
    EaseOutCirc(),
  );

  /// The web's popup backdrop: 150 ms on the standard easing
  /// `cubic-bezier(.4, 0, .2, 1)`.
  static const MotionSpec web = MotionSpec(
    Duration(milliseconds: 150),
    Cubic(0.4, 0, 0.2, 1),
  );

  /// The content preview's dim, which comes with the preview's show: 120 ms
  /// linear. Its still fades on this spec too, on a clock of its own.
  static const MotionSpec contentPreview = MotionSpec(
    Duration(milliseconds: 120),
    Curves.linear,
  );

  /// The content preview's dim when a mouse opened it: 150 ms linear.
  static const MotionSpec contentPreviewPointer = MotionSpec(
    Duration(milliseconds: 150),
    Curves.linear,
  );
}
