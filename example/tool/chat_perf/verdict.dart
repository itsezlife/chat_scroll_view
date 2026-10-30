/// The verdict of a run against a baseline (spec 6.3). Pure Dart.
///
/// Only baseline regressions change the exit status. Absolute targets are
/// findings; a missing baseline is seeded, a version mismatch is stale, an
/// unreachable combination is refused. None of those fail.
library;

import 'dart:math' as math;

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';
import '../../integration_test/chat_perf/trace_counts.dart';
import 'baseline.dart';

/// How far above the baseline max a value may sit: relative to the max, but
/// never less than [floor], so small values do not flap. Working defaults,
/// to be set from the first baselines (spec 14).
final class Margin {
  const Margin({required this.relative, required this.floor});

  final double relative;
  final double floor;

  double allowance(double base) => math.max(base.abs() * relative, floor);
}

/// The margin of metric [name] of [kind]. Traced-pass counts come from a
/// scripted run, so they get a near-exact tolerance (2%, at least one).
Margin marginFor(MetricKind kind, {String name = ''}) =>
    passOf(name) == MetricPass.traced && kind == MetricKind.count
    ? const Margin(relative: 0.02, floor: 1)
    : _marginOf(kind);

Margin _marginOf(MetricKind kind) => switch (kind) {
  MetricKind.share => const Margin(relative: 0.10, floor: 0.02),
  MetricKind.count => const Margin(relative: 0.10, floor: 1),
  MetricKind.ms => const Margin(relative: 0.10, floor: 0.5),
  MetricKind.dp => const Margin(relative: 0.10, floor: 1),
  MetricKind.ratio => const Margin(relative: 0.10, floor: 0.05),
  MetricKind.exact => const Margin(relative: 0, floor: 0),
};

/// Metrics where a lower value is the regression.
bool higherIsBetter(String metric) => metric.endsWith('delivery');

/// Absolute targets (spec 6.3 working defaults): metric name to ceiling.
const Map<String, double> kTargets = {
  'over_budget_share': 0.01,
  'raster_p99_share': 0.60,
};

/// What the run asked for, to check against what it got.
final class Requested {
  const Requested({
    required this.backend,
    required this.semantics,
    this.refreshHz,
  });

  final String backend;

  /// `off`, `on` or `pair`.
  final String semantics;

  /// The refresh rate the run expects, when stated.
  final int? refreshHz;
}

/// What [meta] observed that differs from what was [requested].
List<String> combinationProblems(LaunchMeta meta, Requested requested) => [
  if (meta.backend != requested.backend)
    'asked for backend ${requested.backend}, got ${meta.backend}',
  if (requested.semantics != 'pair' &&
      meta.semanticsMode != requested.semantics)
    'asked for semantics ${requested.semantics}, got ${meta.semanticsMode}',
  if (requested.refreshHz case final hz? when meta.refreshRateHz.round() != hz)
    'asked for ${hz}hz, got ${meta.refreshRateHz.round()}hz',
];

/// Where launches of one run observed different combinations.
List<String> launchDisagreement(List<MetricsDocument> launches) {
  final keys = {for (final l in launches) baselineKey(l.meta)};
  final backends = {for (final l in launches) l.meta.backend};
  return [
    if (keys.length > 1 || backends.length > 1)
      'launches disagree on the combination: ${keys.join(', ')}',
  ];
}

enum VerdictState { compared, seeded, refused }

final class MetricJudgement {
  const MetricJudgement({
    required this.scenario,
    required this.window,
    required this.metric,
    required this.value,
    required this.baseline,
    required this.regressed,
  });

  final String scenario;
  final String window;
  final String metric;
  final double value;
  final BaselineMetric baseline;
  final bool regressed;
}

final class Verdict {
  const Verdict({
    required this.state,
    this.judgements = const [],
    this.stale = const [],
    this.newScenarios = const [],
    this.findings = const [],
    this.refusals = const [],
  });

  final VerdictState state;
  final List<MetricJudgement> judgements;

  /// Scenario ids whose version or corpus differs from the baseline's.
  final List<String> stale;

  /// Scenarios the baseline has never seen.
  final List<String> newScenarios;

  /// Target breaches.
  final List<String> findings;
  final List<String> refusals;

  int get exitCode => judgements.any((j) => j.regressed) ? 1 : 0;
}

bool _regressed(String name, BaselineMetric base, double value) {
  if (base.kind == MetricKind.exact) return value != base.median;
  final margin = marginFor(base.kind, name: name);
  if (higherIsBetter(name))
    return value < base.min - margin.allowance(base.min);
  return value > base.max + margin.allowance(base.max);
}

List<String> _findings(MetricsDocument run) => [
  for (final s in run.scenarios.entries)
    for (final w in s.value.entries)
      for (final m in w.value.entries)
        if (kTargets[m.key] case final ceiling?
            when m.value.role == MetricRole.headline && m.value.value > ceiling)
          '${s.key}  ${w.key}  ${m.key} '
              '${(m.value.value * 100).toStringAsFixed(1)}% '
              'above the target ${(ceiling * 100).toStringAsFixed(0)}%',
];

/// Judges [run] (a run value document) against [baseline].
Verdict judge(MetricsDocument run, Baseline? baseline, {Requested? requested}) {
  final refusals = [
    if (requested != null) ...combinationProblems(run.meta, requested),
  ];
  final findings = _findings(run);
  if (refusals.isNotEmpty) {
    return Verdict(
      state: VerdictState.refused,
      findings: findings,
      refusals: refusals,
    );
  }
  if (baseline == null) {
    return Verdict(state: VerdictState.seeded, findings: findings);
  }
  final corpusStale = baseline.corpusVersion != run.meta.corpusVersion;
  final stale = <String>[];
  final fresh = <String>[];
  final judgements = <MetricJudgement>[];
  for (final s in run.scenarios.entries) {
    final id = s.key.split('@').first;
    final base = baseline.scenarios[s.key];
    if (corpusStale ||
        (base == null &&
            baseline.scenarios.keys.any((k) => k.split('@').first == id))) {
      stale.add(s.key);
      continue;
    }
    if (base == null) {
      fresh.add(s.key);
      continue;
    }
    for (final w in s.value.entries) {
      for (final m in w.value.entries) {
        final b = base[w.key]?[m.key];
        if (b == null || m.value.role != MetricRole.headline) continue;
        judgements.add(
          MetricJudgement(
            scenario: s.key,
            window: w.key,
            metric: m.key,
            value: m.value.value,
            baseline: b,
            regressed: _regressed(m.key, b, m.value.value),
          ),
        );
      }
    }
  }
  return Verdict(
    state: VerdictState.compared,
    judgements: judgements,
    stale: stale,
    newScenarios: fresh,
    findings: findings,
  );
}

String _pct(BaselineMetric b, double v) => switch (b.kind) {
  MetricKind.share => '${(v * 100).toStringAsFixed(1)}%',
  MetricKind.ratio => '${v.toStringAsFixed(2)}x',
  _ => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2),
};

String renderVerdict(Verdict v) {
  final out = <String>[];
  switch (v.state) {
    case VerdictState.seeded:
      out.add('baseline: none for this key; seeded, not failed');
    case VerdictState.refused:
      out
        ..add('baseline: refused to compare')
        ..addAll(['  - ${v.refusals.join('\n  - ')}']);
    case VerdictState.compared:
      for (final j in v.judgements) {
        final b = j.baseline;
        out.add(
          '${j.regressed ? 'REGRESSED' : 'ok       '}  ${j.scenario}  '
          '${j.window}  ${j.metric}'
          '${passOf(j.metric) == MetricPass.traced ? ' [traced]' : ''}  '
          '${_pct(b, j.value)}  '
          '(baseline ${_pct(b, b.median)}, ${_pct(b, b.min)}..${_pct(b, b.max)})',
        );
      }
      for (final s in v.stale) {
        out.add('stale, not compared  $s');
      }
      for (final s in v.newScenarios) {
        out.add('not in the baseline  $s');
      }
      final bad = v.judgements.where((j) => j.regressed).length;
      out.add(
        bad == 0
            ? 'verdict: no regressions'
            : 'verdict: $bad regressed metric${bad == 1 ? '' : 's'}',
      );
  }
  if (v.findings.isNotEmpty) {
    out
      ..add('findings (targets; never fail a run):')
      ..addAll([for (final f in v.findings) '  - $f']);
  }
  return out.join('\n');
}
