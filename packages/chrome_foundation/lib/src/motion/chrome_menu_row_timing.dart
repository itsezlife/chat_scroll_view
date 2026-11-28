import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:flutter/animation.dart';

/// Timing of a menu row that toggles between two states, such as a row
/// whose label names the state its tap leads to.
abstract final class ChromeMenuRowTiming {
  /// How an Android toggle row's label cross-fades to its next state: 300 ms
  /// ease out quint.
  static const MotionSpec labelCrossFade = MotionSpec(
    Duration(milliseconds: 300),
    Curves.easeOutQuint,
  );

  /// A label that changes at once: the platform plays no text animation.
  static const MotionSpec labelInstant = MotionSpec(
    Duration.zero,
    Curves.linear,
  );
}
