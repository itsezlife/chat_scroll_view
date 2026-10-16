import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_speed.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:flutter/widgets.dart';

/// The motion a subtree sees: a role table and a speed.
@immutable
final class ChromeMotionData {
  /// Motion with [motion] played at [speed].
  const ChromeMotionData({
    this.motion = const ChromeMotion.standard(),
    this.speed = ChromeMotionSpeed.normal,
  });

  /// The shipped roles at normal speed: what a subtree with no
  /// `ChromeMotionScope` sees.
  static const ChromeMotionData standard = ChromeMotionData();

  /// The role table, before speed.
  final ChromeMotion motion;

  /// The speed applied to every role.
  final ChromeMotionSpeed speed;

  /// The spec for [role] with [speed] applied to its duration.
  MotionSpec specOf(MotionRole role) => motion[role].withSpeed(speed);

  /// [role]'s duration with [speed] applied.
  Duration durationOf(MotionRole role) => speed.scale(motion[role].duration);

  /// [role]'s curve.
  Curve curveOf(MotionRole role) => motion[role].curve;

  @override
  bool operator ==(Object other) =>
      other is ChromeMotionData &&
      other.motion == motion &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(motion, speed);
}

/// The **chrome motion scope**: supplies the motion roles and the speed to the
/// subtree.
///
/// Optional, unlike the theme and strings scopes: with no scope, widgets see
/// [ChromeMotionData.standard]. The host supplies one to honour reduce-motion
/// (`speed: ChromeMotionSpeed.instant` while `MediaQuery.disableAnimations`
/// is set) or lite mode; nothing in this package reads the platform flag.
///
/// Scopes nest and override only what they name: an inner scope with only a
/// [speed] keeps the outer roles, and one with only [motion] keeps the outer
/// speed.
class ChromeMotionScope extends StatelessWidget {
  /// A scope replacing [motion] and/or [speed] for [child].
  const ChromeMotionScope({
    required this.child,
    this.motion,
    this.speed,
    super.key,
  });

  /// The role table to use below, or null to keep the enclosing one.
  final ChromeMotion? motion;

  /// The speed to use below, or null to keep the enclosing one.
  final ChromeMotionSpeed? speed;

  /// The subtree that sees this motion.
  final Widget child;

  /// The motion at [context]; depends on the nearest scope.
  static ChromeMotionData of(BuildContext context) =>
      maybeOf(context) ?? ChromeMotionData.standard;

  /// The motion of the nearest scope, or null when there is none.
  static ChromeMotionData? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ChromeMotionInherited>()
      ?.data;

  @override
  Widget build(BuildContext context) {
    final outer = of(context);
    return _ChromeMotionInherited(
      data: ChromeMotionData(
        motion: motion ?? outer.motion,
        speed: speed ?? outer.speed,
      ),
      child: child,
    );
  }
}

class _ChromeMotionInherited extends InheritedWidget {
  const _ChromeMotionInherited({required this.data, required super.child});

  final ChromeMotionData data;

  @override
  bool updateShouldNotify(_ChromeMotionInherited oldWidget) =>
      data != oldWidget.data;
}
