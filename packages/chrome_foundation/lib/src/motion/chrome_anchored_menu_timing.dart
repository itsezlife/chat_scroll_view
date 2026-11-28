import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:flutter/animation.dart';

/// Timing of a menu anchored at a control and opened by hovering it, the
/// web's form of a strip's options.
///
/// These are not `ChromeMotion` roles: the reveal is the web's one menu
/// motion and the two holds are pointer timing, which a speed multiplier
/// must not stretch.
abstract final class ChromeAnchoredMenuTiming {
  /// How long a mouse rests on the control before its menu opens (200 ms).
  /// Leaving earlier opens nothing.
  static const Duration hoverOpen = Duration(milliseconds: 200);

  /// How long the pointer may be away from both the control and its menu
  /// before the menu closes (200 ms), so crossing the gap between them
  /// keeps it open. **UNVERIFIED**: a choice equal to [hoverOpen], not a
  /// measurement.
  static const Duration leaveGrace = Duration(milliseconds: 200);

  /// The menu's open and close, both ways: opacity 0 to 1 and scale 0.8 to
  /// 1 over 0.2 s on the standard easing `cubic-bezier(.4, 0, .2, 1)`.
  static const MotionSpec reveal = MotionSpec(
    Duration(milliseconds: 200),
    Cubic(0.4, 0, 0.2, 1),
  );
}
