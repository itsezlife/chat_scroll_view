import 'dart:math' as math;
import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

/// How a spoiler goes when it is revealed, per platform: what the reveal's
/// progress (0 hidden, 1 revealed) uncovers and how long it takes.
///
/// Pure: the cell runs one animation of [totalOf] along [curve] and asks
/// [holeRadiusOf] and [coverOpacityOf] at each progress.
@immutable
sealed class MediaSpoilerReveal {
  const MediaSpoilerReveal._();

  /// A circle grown from the touch point until it covers the cell, over
  /// `clamp(r · durationFactor, min, max)` ms where `r` is the cell's
  /// diagonal in physical pixels, easing in and out.
  const factory MediaSpoilerReveal.circle({
    double durationFactor,
    Duration minDuration,
    Duration maxDuration,
    Curve curve,
  }) = MediaSpoilerReveal$Circle;

  /// A spot opened from the touch point after [MediaSpoilerReveal$Spot.delay],
  /// quicker the nearer the point is to an edge: `base − edgeShortening ·
  /// f`, where `f` (0 at the centre, 1 at an edge) is the point's larger
  /// normalised distance from the centre.
  const factory MediaSpoilerReveal.spot({
    Duration delay,
    Duration base,
    Duration edgeShortening,
    Curve curve,
  }) = MediaSpoilerReveal$Spot;

  /// The cover fades out.
  const factory MediaSpoilerReveal.crossFade({Duration duration, Curve curve}) =
      MediaSpoilerReveal$CrossFade;

  /// The form's name, as the diagnostics name it.
  String get name;

  /// The easing of the reveal's progress (after any delay).
  Curve get curve;

  /// The wait before the reveal starts moving.
  Duration get delay => Duration.zero;

  /// How long the reveal moves for a cell of [size] touched at [origin]
  /// (cell coordinates), on a screen of [devicePixelRatio].
  Duration durationOf(Size size, Offset origin, {double devicePixelRatio = 1});

  /// The whole reveal: [delay] then [durationOf].
  Duration totalOf(Size size, Offset origin, {double devicePixelRatio = 1}) =>
      delay + durationOf(size, origin, devicePixelRatio: devicePixelRatio);

  /// The radius of the hole the reveal has opened at [progress] (the
  /// animation's curved value), or null when it opens no hole.
  double? holeRadiusOf(Size size, Offset origin, double progress);

  /// The cover's opacity at [progress].
  double coverOpacityOf(double progress) => progress >= 1 ? 0 : 1;

  /// The farthest corner of a [size] box from [origin].
  static double farthestCornerOf(Size size, Offset origin) => [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ].map((corner) => (corner - origin).distance).reduce(math.max);
}

/// [MediaSpoilerReveal.circle].
final class MediaSpoilerReveal$Circle extends MediaSpoilerReveal {
  /// See [MediaSpoilerReveal.circle].
  const MediaSpoilerReveal$Circle({
    this.durationFactor = 0.3,
    this.minDuration = const Duration(milliseconds: 250),
    this.maxDuration = const Duration(milliseconds: 550),
    this.curve = Curves.easeInOut,
  }) : super._();

  /// Milliseconds per physical pixel of the circle's final radius.
  final double durationFactor;

  /// The shortest reveal.
  final Duration minDuration;

  /// The longest reveal.
  final Duration maxDuration;

  @override
  final Curve curve;

  @override
  String get name => 'circle';

  /// `clamp(radius · durationFactor, min, max)` ms, [radius] in physical
  /// pixels.
  Duration durationFor(double radius) => Duration(
    microseconds: (radius * durationFactor * 1000).round().clamp(
      minDuration.inMicroseconds,
      maxDuration.inMicroseconds,
    ),
  );

  // The final radius is the cell's diagonal, whatever the touch point, so
  // the duration does not depend on where the cell was touched.
  @override
  Duration durationOf(
    Size size,
    Offset origin, {
    double devicePixelRatio = 1,
  }) => durationFor(
    math.sqrt(size.width * size.width + size.height * size.height) *
        devicePixelRatio,
  );

  @override
  double holeRadiusOf(Size size, Offset origin, double progress) =>
      math.sqrt(size.width * size.width + size.height * size.height) * progress;

  @override
  bool operator ==(Object other) =>
      other is MediaSpoilerReveal$Circle &&
      other.durationFactor == durationFactor &&
      other.minDuration == minDuration &&
      other.maxDuration == maxDuration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(
    MediaSpoilerReveal$Circle,
    durationFactor,
    minDuration,
    maxDuration,
    curve,
  );
}

/// [MediaSpoilerReveal.spot].
final class MediaSpoilerReveal$Spot extends MediaSpoilerReveal {
  /// See [MediaSpoilerReveal.spot].
  const MediaSpoilerReveal$Spot({
    this.delay = const Duration(milliseconds: 100),
    this.base = const Duration(milliseconds: 450),
    this.edgeShortening = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOut,
  }) : super._();

  @override
  final Duration delay;

  /// The reveal's length from the cell's centre.
  final Duration base;

  /// How much shorter a reveal from an edge is.
  final Duration edgeShortening;

  @override
  final Curve curve;

  @override
  String get name => 'spot';

  @override
  Duration durationOf(Size size, Offset origin, {double devicePixelRatio = 1}) {
    if (size.isEmpty) return base;
    final x = (origin.dx / size.width - 0.5).abs() * 2;
    final y = (origin.dy / size.height - 0.5).abs() * 2;
    final edge = math.min(1, math.max(x, y));
    return base - edgeShortening * edge;
  }

  @override
  double holeRadiusOf(Size size, Offset origin, double progress) =>
      MediaSpoilerReveal.farthestCornerOf(size, origin) * progress;

  @override
  bool operator ==(Object other) =>
      other is MediaSpoilerReveal$Spot &&
      other.delay == delay &&
      other.base == base &&
      other.edgeShortening == edgeShortening &&
      other.curve == curve;

  @override
  int get hashCode =>
      Object.hash(MediaSpoilerReveal$Spot, delay, base, edgeShortening, curve);
}

/// [MediaSpoilerReveal.crossFade].
final class MediaSpoilerReveal$CrossFade extends MediaSpoilerReveal {
  /// See [MediaSpoilerReveal.crossFade].
  const MediaSpoilerReveal$CrossFade({
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.linear,
  }) : super._();

  /// The fade's length.
  final Duration duration;

  @override
  final Curve curve;

  @override
  String get name => 'crossFade';

  @override
  Duration durationOf(
    Size size,
    Offset origin, {
    double devicePixelRatio = 1,
  }) => duration;

  @override
  double? holeRadiusOf(Size size, Offset origin, double progress) => null;

  @override
  double coverOpacityOf(double progress) => 1 - progress.clamp(0, 1);

  @override
  bool operator ==(Object other) =>
      other is MediaSpoilerReveal$CrossFade &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode =>
      Object.hash(MediaSpoilerReveal$CrossFade, duration, curve);
}
