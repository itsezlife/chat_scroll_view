/// Assembling the windows of a scale scenario run at several history sizes
/// (spec 7.5). Pure Dart.
library;

import 'metrics.dart';

/// The history tiers of the scale family: 1k is the reference.
const kScaleTiers = [1000, 20000, 200000];

/// Metrics that carry a ratio against the reference tier: the headline trio
/// and the diagnostics the scale scripts record.
const _scaleRatioMetrics = [
  'build_p99_share',
  'raster_p99_share',
  'over_budget_share',
  'settle_ms',
  'land_frames_max',
  'travel_frames_max',
];

/// `1000` as `1k`, `200000` as `200k`.
String tierLabel(int history) =>
    history % 1000 == 0 ? '${history ~/ 1000}k' : '$history';

/// One window map per window and tier: `<window>.<tier>` holds the metrics of
/// that tier, and `<window>.ratio_<tier>` the ratios against the first tier,
/// for every tier after it.
Map<String, Map<String, Metric>> assembleTiers(
  Map<int, Map<String, Map<String, Metric>>> byTier,
  List<String> windows,
) {
  final tiers = byTier.keys.toList();
  final result = <String, Map<String, Metric>>{};
  for (final w in windows) {
    final base = byTier[tiers.first]?[w];
    for (final t in tiers) {
      final metrics = byTier[t]?[w];
      if (metrics == null) continue;
      result['$w.${tierLabel(t)}'] = metrics;
      if (t != tiers.first && base != null) {
        result['$w.ratio_${tierLabel(t)}'] = ratioMetrics(
          base: base,
          other: metrics,
          names: _scaleRatioMetrics,
        );
      }
    }
  }
  return result;
}
