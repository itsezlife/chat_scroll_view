import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// The numbers and rules of a swipe pager: when a drag becomes a swipe, when
/// a release goes on to the next page, and how long the settle takes.
///
/// The defaults are the values of a mobile pager's gestures and settle.
/// Distances are in logical pixels. The release velocities are in physical
/// pixels per second, and are compared against a logical velocity times the
/// device pixel ratio: on a phone the same flick
/// commits on both, on a low-density screen it takes a faster one.
///
/// Every rule takes the axis of the pager as its main axis: `velocity` is
/// along it and `crossVelocity` across it.
@immutable
class SwipePagerPhysics {
  /// The rules, with these defaults.
  const SwipePagerPhysics({
    this.claimSlop = 0.3 / 2.54 * 160,
    this.crossAxisSlop = 8,
    this.flingStartVelocity = 3000,
    this.commitFraction = 1 / 3,
    this.commitVelocity = 3500,
    this.caughtCommitVelocity = 1500,
    this.maxVelocity = 8000,
    this.minSettle = const Duration(milliseconds: 150),
    this.maxSettle = const Duration(milliseconds: 600),
    this.settleCurve = const _QuinticOut(),
  });

  /// How far along the main axis a drag moves before the pager claims it,
  /// in logical pixels, provided it has not first moved [crossAxisSlop]
  /// across.
  ///
  /// 0.3 cm, at the 160 logical pixels per inch a logical pixel stands for:
  /// about 18.9. It is above the platform's own drag slop
  /// (18, or 8 on Android), so a nested scroller along the same axis claims
  /// its drag first.
  final double claimSlop;

  /// How far across the axis a drag moves before the pager lets it go, in
  /// logical pixels.
  ///
  /// The pager gives way as soon as a vertical list in the page starts
  /// scrolling, which a list does past the platform touch slop of
  /// 8 dp. Together with [claimSlop] a straight drag pages only within about
  /// 23 degrees of the axis.
  final double crossAxisSlop;

  /// The velocity a release must reach, in physical pixels per second, to
  /// start a swipe that never went past [claimSlop], while it is faster
  /// along the axis than across.
  final double flingStartVelocity;

  /// How much of a page a drag from rest covers to go on to the next page
  /// without a fling.
  final double commitFraction;

  /// The velocity, in physical pixels per second, that lets a drag from rest
  /// go on to the next page however short it was, while it is faster along
  /// the axis than across. Its direction does not matter.
  final double commitVelocity;

  /// The velocity, in physical pixels per second, over which a drag that
  /// caught a settle goes the way it is flung; slower, it goes to the nearer
  /// page.
  final double caughtCommitVelocity;

  /// The largest velocity a release is taken to have, in logical pixels per
  /// second, on each axis.
  final double maxVelocity;

  /// The shortest settle after a release.
  final Duration minSettle;

  /// The longest settle after a release.
  final Duration maxSettle;

  /// The curve of the settle after a release: a quintic ease out,
  /// `1 + (t - 1)^5`.
  final Curve settleCurve;

  /// Whether a release that never went past [claimSlop] starts a swipe.
  ///
  /// [velocity] and [crossVelocity] are logical pixels per second.
  bool startsFling({
    required double velocity,
    required double crossVelocity,
    required double devicePixelRatio,
  }) =>
      velocity.abs() * devicePixelRatio >= flingStartVelocity &&
      velocity.abs() > crossVelocity.abs();

  /// Whether a release goes on to the incoming page, rather than back.
  ///
  /// [fraction] is how much of the incoming page shows, 0..1. [velocity] is
  /// in logical pixels per second, positive toward the incoming page, and
  /// [crossVelocity] across the axis. [caught] tells a drag that caught a
  /// settle from one that started at rest.
  bool commits({
    required double fraction,
    required double velocity,
    required double crossVelocity,
    required bool caught,
    required double devicePixelRatio,
  }) {
    final along = velocity.abs() * devicePixelRatio;
    if (caught) {
      if (along > caughtCommitVelocity) return velocity > 0;
      return fraction >= 0.5;
    }
    final stays =
        fraction < commitFraction &&
        (along < commitVelocity || velocity.abs() < crossVelocity.abs());
    return !stays;
  }

  /// How long the settle after a release takes, to cover [remaining] of a
  /// page [extent] long at a release [velocity] (any unit, the same for all
  /// three, per second).
  ///
  /// The snap rule: with a velocity, four times the time to
  /// cover half the page plus a sine-weighted share of the other half; with
  /// none, 100 ms plus 100 ms per page left. Clamped to [minSettle] ..
  /// [maxSettle].
  Duration settleDuration({
    required double remaining,
    required double extent,
    required double velocity,
  }) {
    final half = extent / 2;
    final ratio = extent > 0 ? math.min(1, remaining / extent) : 0.0;
    final distance = half + half * math.sin((ratio - 0.5) * 0.47123894);
    final speed = velocity.abs();
    final ms = speed > 0
        ? 4 * (1000 * (distance / speed).abs()).round()
        : ((extent > 0 ? remaining / extent : 0) + 1) * 100;
    return Duration(
      milliseconds: ms.round().clamp(
        minSettle.inMilliseconds,
        maxSettle.inMilliseconds,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwipePagerPhysics &&
      other.claimSlop == claimSlop &&
      other.crossAxisSlop == crossAxisSlop &&
      other.flingStartVelocity == flingStartVelocity &&
      other.commitFraction == commitFraction &&
      other.commitVelocity == commitVelocity &&
      other.caughtCommitVelocity == caughtCommitVelocity &&
      other.maxVelocity == maxVelocity &&
      other.minSettle == minSettle &&
      other.maxSettle == maxSettle &&
      other.settleCurve == settleCurve;

  @override
  int get hashCode => Object.hash(
    claimSlop,
    crossAxisSlop,
    flingStartVelocity,
    commitFraction,
    commitVelocity,
    caughtCommitVelocity,
    maxVelocity,
    minSettle,
    maxSettle,
    settleCurve,
  );
}

/// `1 + (t - 1)^5`: the settle interpolator.
class _QuinticOut extends Curve {
  const _QuinticOut();

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return u * u * u * u * u + 1;
  }
}
