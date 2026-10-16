import 'package:chrome_foundation/src/motion/chrome_motion_speed.dart';
import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

/// A duration and a curve: what one **motion role** plays.
@immutable
final class MotionSpec {
  /// A spec playing [curve] over [duration].
  const MotionSpec(this.duration, this.curve);

  /// How long the motion runs at normal speed; never negative.
  final Duration duration;

  /// The easing applied over [duration].
  final Curve curve;

  /// This spec with [duration] scaled by [speed]; the curve is unchanged.
  MotionSpec withSpeed(ChromeMotionSpeed speed) =>
      MotionSpec(speed.scale(duration), curve);

  @override
  bool operator ==(Object other) =>
      other is MotionSpec && other.duration == duration && other.curve == curve;

  @override
  int get hashCode => Object.hash(duration, curve);

  @override
  String toString() => 'MotionSpec($duration, $curve)';
}
