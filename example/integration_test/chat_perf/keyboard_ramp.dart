/// Synthetic keyboard-inset curves and the per-frame arithmetic that splits
/// the engine's compensation error from the host's pad behaviour (spec 7.3).
///
/// Pure Dart: the on-device keyboard context and the unit tests share it.
library;

import 'dart:math' as math;

import 'metrics.dart';

/// One monotone curve of the inset over time, as a fraction of the full
/// keyboard height.
final class InsetCurve {
  /// [points] are `(ms, fraction)` pairs, strictly increasing in time; the
  /// first is at 0 ms.
  const InsetCurve(this.points);

  final List<(double ms, double fraction)> points;

  /// When the curve reaches its last point.
  double get durationMs => points.last.$1;

  /// The fraction at [ms], linear between points, held outside the curve.
  double at(double ms) {
    if (ms <= 0) return points.first.$2;
    if (ms >= durationMs) return points.last.$2;
    var i = 1;
    while (points[i].$1 < ms) {
      i++;
    }
    final (t0, f0) = points[i - 1];
    final (t1, f1) = points[i];
    return f0 + (f1 - f0) * (ms - t0) / (t1 - t0);
  }

  /// The same shape at [factor] of the height: a low-amplitude primer.
  InsetCurve scaled(double factor) =>
      InsetCurve([for (final (ms, f) in points) (ms, f * factor)]);
}

/// An open and a close curve, with the keyboard height they run to.
final class InsetCurveProfile {
  const InsetCurveProfile({
    required this.name,
    required this.heightDp,
    required this.open,
    required this.close,
  });

  final String name;

  /// The settled keyboard height the fractions scale to, in logical pixels.
  final double heightDp;
  final InsetCurve open;
  final InsetCurve close;

  /// The Android system keyboard on the SM-S938B at 358 dp (1008 px at 2.8125),
  /// from the device probe's per-frame trace (`probe-09`, launch 2, tail
  /// cycle). Time zero is the last frame before the inset moved. Samples are
  /// the observed frames, about 17 ms apart, so a driver faster than that
  /// interpolates between them.
  static const androidRamp = InsetCurveProfile(
    name: 'android_ramp',
    heightDp: 358,
    open: InsetCurve([
      (0, 0),
      (15.7, 79 / 1008),
      (41.2, 310 / 1008),
      (57.6, 483 / 1008),
      (75.4, 611 / 1008),
      (92.4, 699 / 1008),
      (108.8, 762 / 1008),
      (125.1, 813 / 1008),
      (141.9, 851 / 1008),
      (158.5, 885 / 1008),
      (175.1, 911 / 1008),
      (192.1, 932 / 1008),
      (208.2, 950 / 1008),
      (224.3, 965 / 1008),
      (241.2, 976 / 1008),
      (257.5, 986 / 1008),
      (274.0, 993 / 1008),
      (291.3, 999 / 1008),
      (308.3, 1003 / 1008),
      (324.6, 1006 / 1008),
      (340.9, 1007 / 1008),
      (358.1, 1),
    ]),
    close: InsetCurve([
      (0, 1),
      (16.3, 996 / 1008),
      (36.4, 953 / 1008),
      (54.3, 855 / 1008),
      (71.8, 691 / 1008),
      (83.8, 531 / 1008),
      (100.6, 396 / 1008),
      (117.2, 298 / 1008),
      (134.2, 225 / 1008),
      (154.3, 167 / 1008),
      (169.3, 121 / 1008),
      (183.4, 88 / 1008),
      (200.9, 61 / 1008),
      (216.7, 41 / 1008),
      (232.6, 24 / 1008),
      (249.1, 13 / 1008),
      (266.3, 6 / 1008),
      (284.3, 2 / 1008),
      (302.9, 0),
    ]),
  );
}

/// One frame of a ramp, sampled after the frame. Units are in the names:
/// [insetPx] is physical pixels, [padDp] and [anchorOffsetDp] logical.
final class RampSample {
  const RampSample({
    required this.tMs,
    required this.insetPx,
    required this.padDp,
    required this.anchorId,
    required this.anchorOffsetDp,
  });

  final double tMs;
  final double insetPx;
  final double padDp;
  final int anchorId;
  final double anchorOffsetDp;
}

Metric _m(
  double v,
  MetricKind kind, [
  MetricRole role = MetricRole.diagnostic,
]) => Metric(v, kind: kind, role: role);

/// The ramp metrics of a still window (spec 7.3) from its per-frame [samples].
///
/// [expectedFrames] is how many frames the ramp should deliver: its duration
/// over the vsync budget. Invariant 16 says the anchor moves by the pad's
/// change, so the engine error of a frame is |anchor shift + pad shift|; the
/// pad's swing past its settled value is the host's, whatever the engine does.
Map<String, Metric> rampMetrics(
  List<RampSample> samples, {
  required double expectedFrames,
}) {
  if (samples.isEmpty) return {};
  var compError = 0.0;
  var jumps = 0;
  var changes = 0;
  double? firstChange;
  double? lastChange;
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1];
    final b = samples[i];
    if (a.anchorId != b.anchorId) {
      jumps++;
    } else {
      compError = math.max(
        compError,
        (b.anchorOffsetDp - a.anchorOffsetDp + b.padDp - a.padDp).abs(),
      );
    }
    if (a.insetPx != b.insetPx) {
      changes++;
      firstChange ??= b.tMs;
      lastChange = b.tMs;
    }
  }
  final start = samples.first;
  final end = samples.last;
  final pads = [for (final s in samples) s.padDp];
  final overshoot = end.padDp >= start.padDp
      ? math.max<double>(0, pads.reduce(math.max) - end.padDp)
      : math.max<double>(0, end.padDp - pads.reduce(math.min));
  final origin = start.tMs;
  return {
    'engine.comp_error_dp': _m(compError, MetricKind.dp, MetricRole.target),
    'host.pad_overshoot_dp': _m(overshoot, MetricKind.dp),
    'jump.messages': _m(jumps.toDouble(), MetricKind.exact),
    // Context for the numbers above: how far the pad moved and how far the
    // anchor travelled, so an error of zero is not an absent change.
    'pad.start_dp': _m(start.padDp, MetricKind.dp),
    'pad.end_dp': _m(end.padDp, MetricKind.dp),
    'pad.min_dp': _m(pads.reduce(math.min), MetricKind.dp),
    'pad.max_dp': _m(pads.reduce(math.max), MetricKind.dp),
    'anchor.travel_dp': _m(
      end.anchorOffsetDp - start.anchorOffsetDp,
      MetricKind.dp,
    ),
    if (firstChange case final first?) ...{
      'ramp.first_inset_ms': _m(first - origin, MetricKind.ms),
      'ramp.duration_ms': _m(lastChange! - first, MetricKind.ms),
    },
    'ramp.delivery': _m(
      expectedFrames <= 0 ? 0 : changes / expectedFrames,
      MetricKind.share,
      MetricRole.headline,
    ),
  };
}

/// Where a run ended: the anchor and the pad.
final class RampEnd {
  const RampEnd({
    required this.anchorId,
    required this.anchorOffsetDp,
    required this.padDp,
  });

  final int anchorId;
  final double anchorOffsetDp;
  final double padDp;
}

/// The stability of a moving window against its control run without the inset
/// change: the same gesture ends in the same place, shifted only by the pad.
///
/// With different end anchors the offsets are not comparable, so only the
/// message distance is reported.
Map<String, Metric> pairedControlMetrics({
  required RampEnd withRamp,
  required RampEnd control,
}) {
  final jump = (withRamp.anchorId - control.anchorId).abs();
  return {
    'jump.messages': _m(jump.toDouble(), MetricKind.exact),
    if (jump == 0)
      'engine.comp_error_dp': _m(
        (withRamp.anchorOffsetDp -
                control.anchorOffsetDp +
                withRamp.padDp -
                control.padDp)
            .abs(),
        MetricKind.dp,
        MetricRole.target,
      ),
  };
}
