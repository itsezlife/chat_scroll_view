import 'package:chrome_foundation/src/motion/chrome_motion_speed.dart';
import 'package:meta/meta.dart';

/// How the particles of a hidden spoiler move.
///
/// The numbers are the reference client's, measured in the particle
/// prototype: a speed and a life drawn uniformly from a range per particle,
/// and a fixed tick. Speeds are logical pixels per second, so they do not
/// depend on the display density.
@immutable
final class SpoilerParticleMotion {
  /// Particle motion; the defaults are [standard].
  const SpoilerParticleMotion({
    this.minSpeed = 4,
    this.maxSpeed = 10,
    this.minLife = const Duration(seconds: 1),
    this.maxLife = const Duration(seconds: 3),
    this.framesPerSecond = 30,
  }) : assert(
         minSpeed >= 0 && maxSpeed >= minSpeed,
         'the speed range must be non-negative and ordered',
       ),
       assert(framesPerSecond > 0, 'the tick rate must be positive');

  /// 4-10 dp/s, 1-3 s of life, 30 frames per second.
  static const SpoilerParticleMotion standard = SpoilerParticleMotion();

  /// Slowest particle, in logical pixels per second.
  final double minSpeed;

  /// Fastest particle, in logical pixels per second.
  final double maxSpeed;

  /// Shortest particle life.
  final Duration minLife;

  /// Longest particle life.
  final Duration maxLife;

  /// How often the particles are redrawn.
  final int framesPerSecond;

  /// The time between two redraws, whole microseconds.
  Duration get tick =>
      Duration(microseconds: Duration.microsecondsPerSecond ~/ framesPerSecond);

  /// The tick under [speed], or null when the particles stand still.
  ///
  /// An instant speed (reduce-motion, lite mode) draws one frame and never
  /// redraws, the frame-0 behaviour of both reference clients. A scaled speed
  /// leaves the tick alone: it is a frame rate, and particle speeds are
  /// already per second.
  Duration? tickAt(ChromeMotionSpeed speed) => speed.isInstant ? null : tick;

  @override
  bool operator ==(Object other) =>
      other is SpoilerParticleMotion &&
      other.minSpeed == minSpeed &&
      other.maxSpeed == maxSpeed &&
      other.minLife == minLife &&
      other.maxLife == maxLife &&
      other.framesPerSecond == framesPerSecond;

  @override
  int get hashCode =>
      Object.hash(minSpeed, maxSpeed, minLife, maxLife, framesPerSecond);

  @override
  String toString() =>
      'SpoilerParticleMotion($minSpeed-$maxSpeed dp/s, '
      '${minLife.inMilliseconds}-${maxLife.inMilliseconds} ms, '
      '$framesPerSecond fps)';
}
