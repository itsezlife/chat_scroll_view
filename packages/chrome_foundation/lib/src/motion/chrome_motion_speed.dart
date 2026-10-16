import 'package:meta/meta.dart';

/// How fast chrome motion runs relative to its role durations.
///
/// This is the single input behind reduce-motion and lite mode: a host maps
/// `MediaQuery.disableAnimations` (or its own lite flag) to [instant] and
/// supplies it through a `ChromeMotionScope`. Components never read the
/// platform flag themselves.
@immutable
final class ChromeMotionSpeed {
  /// Runs motion [multiplier] times as fast: `times(2)` halves every
  /// duration, `times(0.5)` doubles it.
  const ChromeMotionSpeed.times(double multiplier)
    : assert(
        multiplier > 0 && multiplier < double.infinity,
        'multiplier must be positive and finite; use ChromeMotionSpeed.instant '
        'to remove motion.',
      ),
      _multiplier = multiplier;

  const ChromeMotionSpeed._instant() : _multiplier = double.infinity;

  /// Role durations as designed.
  static const ChromeMotionSpeed normal = ChromeMotionSpeed.times(1);

  /// Every duration is [Duration.zero]: state changes land on the next frame.
  static const ChromeMotionSpeed instant = ChromeMotionSpeed._instant();

  final double _multiplier;

  /// Whether every duration collapses to zero.
  bool get isInstant => _multiplier.isInfinite;

  /// [duration] divided by the multiplier, rounded to whole microseconds.
  Duration scale(Duration duration) {
    if (isInstant) return Duration.zero;
    if (_multiplier == 1) return duration;
    return Duration(
      microseconds: (duration.inMicroseconds / _multiplier).round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChromeMotionSpeed && other._multiplier == _multiplier;

  @override
  int get hashCode => _multiplier.hashCode;

  @override
  String toString() => isInstant
      ? 'ChromeMotionSpeed.instant'
      : 'ChromeMotionSpeed.times($_multiplier)';
}
