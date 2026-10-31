/// Run values and baselines (spec 6.3, 6.4, 9). Pure Dart.
///
/// A launch's document is merged with its cold launches ([unionDocuments]);
/// a run value is the per-metric median over launches ([medianOf]); a
/// [Baseline] keeps the median, min and max per metric. The baseline file is
/// metrics only: sidecars, per-frame arrays and timelines never enter it.
library;

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';

/// Launches a baseline needs before it may be promoted.
const int kMinBaselineLaunches = 5;

/// Bumped when the baseline file's shape changes.
const int kBaselineSchemaVersion = 1;

double median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// One launch's document from the shared-process document and the documents of
/// its cold launches. Metadata comes from the first.
MetricsDocument unionDocuments(List<MetricsDocument> docs) {
  final scenarios = <String, Map<String, Map<String, Metric>>>{};
  for (final d in docs) {
    scenarios.addAll(d.scenarios);
  }
  return MetricsDocument(meta: docs.first.meta, scenarios: scenarios);
}

/// Every `scenario / window / metric` that any of [launches] holds, with the
/// values it has, in first-seen order.
Map<(String, String, String), List<Metric>> _collect(
  List<MetricsDocument> launches,
) {
  final out = <(String, String, String), List<Metric>>{};
  for (final doc in launches) {
    for (final s in doc.scenarios.entries) {
      for (final w in s.value.entries) {
        for (final m in w.value.entries) {
          (out[(s.key, w.key, m.key)] ??= []).add(m.value);
        }
      }
    }
  }
  return out;
}

/// The run value: the median of each metric over [launches].
MetricsDocument medianOf(List<MetricsDocument> launches) {
  final scenarios = <String, Map<String, Map<String, Metric>>>{};
  for (final e in _collect(launches).entries) {
    final (s, w, m) = e.key;
    final first = e.value.first;
    scenarios.putIfAbsent(s, () => {}).putIfAbsent(w, () => {})[m] = Metric(
      median([for (final v in e.value) v.value]),
      kind: first.kind,
      role: first.role,
    );
  }
  return MetricsDocument(meta: launches.first.meta, scenarios: scenarios);
}

/// `<device-model>.<backend>.<refresh>hz.<sem-mode>`, as observed.
String baselineKey(LaunchMeta meta) {
  final model = meta.device.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  return '$model.${meta.backend}.${meta.refreshRateHz.round()}hz.'
      'sem-${meta.semanticsRequested}';
}

/// One metric's spread over a baseline's launches.
final class BaselineMetric {
  const BaselineMetric({
    required this.kind,
    required this.role,
    required this.median,
    required this.min,
    required this.max,
  });

  factory BaselineMetric.fromJson(Map<String, Object?> json) => BaselineMetric(
    kind: MetricKind.values.byName(json['kind']! as String),
    role: MetricRole.values.byName(json['role']! as String),
    median: (json['median']! as num).toDouble(),
    min: (json['min']! as num).toDouble(),
    max: (json['max']! as num).toDouble(),
  );

  final MetricKind kind;
  final MetricRole role;
  final double median;
  final double min;
  final double max;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'role': role.name,
    'median': median,
    'min': min,
    'max': max,
  };
}

/// A metrics-only baseline document.
final class Baseline {
  const Baseline({
    required this.key,
    required this.label,
    required this.device,
    required this.backend,
    required this.refreshRateHz,
    required this.semantics,
    required this.corpusVersion,
    required this.launches,
    required this.discarded,
    required this.scenarios,
    this.reason,
  });

  /// The baseline of [launches] (one document per launch, cold launches
  /// already merged in).
  factory Baseline.fromLaunches(
    List<MetricsDocument> launches, {
    required String label,
    int discarded = 0,
  }) {
    final meta = launches.first.meta;
    final scenarios = <String, Map<String, Map<String, BaselineMetric>>>{};
    for (final e in _collect(launches).entries) {
      final (s, w, m) = e.key;
      final values = [for (final v in e.value) v.value];
      scenarios
          .putIfAbsent(s, () => {})
          .putIfAbsent(w, () => {})[m] = BaselineMetric(
        kind: e.value.first.kind,
        role: e.value.first.role,
        median: median(values),
        min: values.reduce((a, b) => a < b ? a : b),
        max: values.reduce((a, b) => a > b ? a : b),
      );
    }
    return Baseline(
      key: baselineKey(meta),
      label: label,
      device: meta.device,
      backend: meta.backend,
      refreshRateHz: meta.refreshRateHz,
      semantics: meta.semanticsRequested,
      corpusVersion: meta.corpusVersion,
      launches: launches.length,
      discarded: discarded,
      scenarios: scenarios,
    );
  }

  factory Baseline.fromJson(Map<String, Object?> json) => Baseline(
    key: json['key']! as String,
    label: json['label']! as String,
    device: json['device']! as String,
    backend: json['backend']! as String,
    refreshRateHz: (json['refreshRateHz']! as num).toDouble(),
    semantics: json['semantics']! as String,
    corpusVersion: json['corpusVersion']! as int,
    launches: json['launches']! as int,
    discarded: json['discardedLaunches']! as int,
    reason: json['reason'] as String?,
    scenarios: {
      for (final s in (json['scenarios']! as Map<String, Object?>).entries)
        s.key: {
          for (final w in (s.value! as Map<String, Object?>).entries)
            w.key: {
              for (final m in (w.value! as Map<String, Object?>).entries)
                m.key: BaselineMetric.fromJson(
                  m.value! as Map<String, Object?>,
                ),
            },
        },
    },
  );

  final String key;

  /// The run label that produced it.
  final String label;
  final String device;
  final String backend;
  final double refreshRateHz;
  final String semantics;
  final int corpusVersion;
  final int launches;
  final int discarded;

  /// The one-line reason a promote recorded; null on a candidate.
  final String? reason;

  /// `id@version` -> window -> metric name -> spread.
  final Map<String, Map<String, Map<String, BaselineMetric>>> scenarios;

  /// This baseline with every metric of [other] added or replaced, window by
  /// window; the rest is kept. Adds the traced pass's counts to a baseline of
  /// timing launches.
  Baseline withMetricsOf(Baseline other) {
    final merged = {
      for (final s in scenarios.entries)
        s.key: {
          for (final w in s.value.entries) w.key: {...w.value},
        },
    };
    for (final s in other.scenarios.entries) {
      for (final w in s.value.entries) {
        merged
            .putIfAbsent(s.key, () => {})
            .putIfAbsent(w.key, () => {})
            .addAll(w.value);
      }
    }
    return Baseline(
      key: key,
      label: other.label,
      device: device,
      backend: backend,
      refreshRateHz: refreshRateHz,
      semantics: semantics,
      corpusVersion: corpusVersion,
      launches: launches,
      discarded: discarded,
      scenarios: merged,
    );
  }

  Baseline withReason(String reason) => Baseline(
    key: key,
    label: label,
    device: device,
    backend: backend,
    refreshRateHz: refreshRateHz,
    semantics: semantics,
    corpusVersion: corpusVersion,
    launches: launches,
    discarded: discarded,
    scenarios: scenarios,
    reason: reason,
  );

  Map<String, Object?> toJson() => {
    'schema': kBaselineSchemaVersion,
    'key': key,
    'label': label,
    'device': device,
    'backend': backend,
    'refreshRateHz': refreshRateHz,
    'semantics': semantics,
    'corpusVersion': corpusVersion,
    'launches': launches,
    'discardedLaunches': discarded,
    'reason': ?reason,
    'scenarios': {
      for (final s in scenarios.entries)
        s.key: {
          for (final w in s.value.entries)
            w.key: {for (final m in w.value.entries) m.key: m.value.toJson()},
        },
    },
  };
}

/// Why [candidate] may not be promoted with [reason]; empty when it may.
List<String> promoteProblems(Baseline candidate, String reason) => [
  if (candidate.launches < kMinBaselineLaunches)
    'the candidate has ${candidate.launches} launches; '
        'at least $kMinBaselineLaunches are required',
  if (candidate.discarded > 0)
    'the candidate has ${candidate.discarded} discarded launches; '
        'rerun the baseline',
  if (reason.trim().isEmpty)
    'a one-line reason is required (--reason "...")'
  else if (reason.trim().contains('\n'))
    'the reason must be one line',
];

String _format(BaselineMetric m, double v) => switch (m.kind) {
  MetricKind.share => '${(v * 100).toStringAsFixed(1)}%',
  MetricKind.ratio => '${v.toStringAsFixed(2)}x',
  _ => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2),
};

/// The headline metrics of [candidate] against [current]'s, one line each.
String headlineDiff(Baseline? current, Baseline candidate) {
  final lines = <String>[
    if (current == null)
      'no current baseline for ${candidate.key}: every metric is new',
  ];
  for (final s in candidate.scenarios.entries) {
    for (final w in s.value.entries) {
      for (final m in w.value.entries) {
        if (m.value.role != MetricRole.headline) continue;
        final old = current?.scenarios[s.key]?[w.key]?[m.key];
        final to = _format(m.value, m.value.median);
        final from = switch (old) {
          final o? => _format(o, o.median),
          null => 'new',
        };
        lines.add('${s.key}  ${w.key}  ${m.key}  $from -> $to');
      }
    }
  }
  return lines.join('\n');
}
