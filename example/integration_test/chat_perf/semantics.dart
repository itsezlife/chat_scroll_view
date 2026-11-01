/// Semantics modes of a chat performance launch (spec 6.5). Pure Dart.
///
/// The shipping configuration has semantics off, so every scenario runs off by
/// default. `pair` runs a scenario off and then on in the same launch and
/// reports the on/off ratio.
library;

import 'metrics.dart';

/// Which semantics states a launch measures.
enum SemanticsRun {
  off,
  on,
  pair;

  /// Parses a `--semantics` value; empty means the default, [off].
  static SemanticsRun parse(String value) {
    if (value.isEmpty) return off;
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    throw FormatException('semantics must be off, on or pair', value);
  }

  /// The `semanticsEnabled` states one scenario runs under, in order.
  List<bool> get passes => switch (this) {
    off => const [false],
    on => const [true],
    pair => const [false, true],
  };
}

/// Headline metrics that carry a semantics on/off ratio.
const _ratioMetrics = [
  'build_p99_share',
  'raster_p99_share',
  'over_budget_share',
];

/// Trace events the framework emits for semantics work.
final _semanticsEvent = RegExp('^(Semantics|ensureGeometry)');

/// How many semantics trace events a timeline (as `Timeline.toJson`) holds.
int countSemanticsEvents(Map<String, Object?> timeline) {
  final events = switch (timeline['traceEvents']) {
    final List<Object?> list => list,
    _ => const <Object?>[],
  };
  var count = 0;
  for (final event in events) {
    if (event case {
      'name': final name,
    } when '$name'.startsWith(_semanticsEvent)) {
      count++;
    }
  }
  return count;
}

/// Each headline metric of [on] divided by [off]; a metric absent from either
/// or zero in [off] has no ratio.
Map<String, Metric> semanticsRatio({
  required Map<String, Metric> off,
  required Map<String, Metric> on,
}) => ratioMetrics(base: off, other: on, names: _ratioMetrics);
