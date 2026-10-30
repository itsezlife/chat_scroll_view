import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';
import '../../tool/chat_perf/baseline.dart';
import '../../tool/chat_perf/verdict.dart';

Metric _share(double v, {MetricRole role = MetricRole.headline}) =>
    Metric(v, kind: MetricKind.share, role: role);

MetricsDocument _doc(
  Map<String, Map<String, Map<String, Metric>>> scenarios, {
  String device = 'SM-S938B',
  String backend = 'impeller',
  double hz = 120,
  String semantics = 'off',
  int corpus = 1,
}) => MetricsDocument(
  meta: LaunchMeta(
    device: device,
    os: 'Android 16',
    flutterVersion: '3',
    dartVersion: '3',
    backend: backend,
    refreshRateHz: hz,
    semanticsMode: semantics,
    semanticsRequested: semantics,
    corpusVersion: corpus,
    buildMode: 'profile',
  ),
  scenarios: scenarios,
);

MetricsDocument _one(
  double raster, {
  String id = 'scroll.drag_slow@1',
  int corpus = 1,
  Metric? extra,
}) => _doc({
  id: {
    'drag': {'raster_p99_share': _share(raster), 'x': ?extra},
  },
}, corpus: corpus);

Baseline _baseline(List<double> rasters, {int corpus = 1, int discarded = 0}) =>
    Baseline.fromLaunches(
      [for (final r in rasters) _one(r, corpus: corpus)],
      label: 'b',
      discarded: discarded,
    );

const _exact3 = Metric(3, kind: MetricKind.exact, role: MetricRole.headline);
const _exact4 = Metric(4, kind: MetricKind.exact, role: MetricRole.headline);

void main() {
  group('merge', () {
    test('median of odd and even counts', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 2, 3]), 2.5);
    });

    test('run value is the per-metric median across launches', () {
      final run = medianOf([_one(0.2), _one(0.9), _one(0.3)]);
      expect(
        run
            .scenarios['scroll.drag_slow@1']!['drag']!['raster_p99_share']!
            .value,
        0.3,
      );
    });

    test('union joins the shared-process launch and a cold launch', () {
      final u = unionDocuments([
        _one(0.2),
        _one(0.5, id: 'scroll.first_scroll@1'),
      ]);
      expect(u.scenarios.keys, ['scroll.drag_slow@1', 'scroll.first_scroll@1']);
    });
  });

  group('baseline', () {
    test('stores median, min and max per metric', () {
      final b = _baseline([0.2, 0.4, 0.3, 0.25, 0.5]);
      final m =
          b.scenarios['scroll.drag_slow@1']!['drag']!['raster_p99_share']!;
      expect((m.median, m.min, m.max), (0.3, 0.2, 0.5));
      expect(b.launches, 5);
    });

    test('key names device, backend, refresh and semantics', () {
      expect(baselineKey(_one(0.1).meta), 'sm-s938b.impeller.120hz.sem-off');
    });

    test('json holds metrics only: no frame arrays or timelines', () {
      final text = _baseline([0.2, 0.3, 0.4, 0.5, 0.6]).toJson().toString();
      expect(text, isNot(contains('buildMs')));
      expect(text, isNot(contains('traceEvents')));
    });

    test('json round trip', () {
      final b = _baseline([0.2, 0.3, 0.4, 0.5, 0.6]);
      expect(Baseline.fromJson(b.toJson()).toJson(), b.toJson());
    });
  });

  group('judge', () {
    final base = _baseline([0.20, 0.22, 0.21, 0.23, 0.24]);

    test('within max plus margin is ok', () {
      final v = judge(_one(0.25), base);
      expect(v.judgements.single.regressed, isFalse);
      expect(v.exitCode, 0);
    });

    test('above max by more than the margin regresses, exit 1', () {
      final v = judge(_one(0.40), base);
      expect(v.judgements.single.regressed, isTrue);
      expect(v.exitCode, 1);
    });

    test('the absolute floor stops small values flapping', () {
      final tiny = _baseline([0.001, 0.001, 0.001, 0.001, 0.001]);
      expect(judge(_one(0.015), tiny).exitCode, 0);
      expect(judge(_one(0.05), tiny).exitCode, 1);
    });

    test('exact metrics need equality', () {
      final b = Baseline.fromLaunches([
        for (var i = 0; i < 5; i++) _one(0.2, extra: _exact3),
      ], label: 'b');
      expect(judge(_one(0.2, extra: _exact3), b).exitCode, 0);
      expect(judge(_one(0.2, extra: _exact4), b).exitCode, 1);
    });

    test('diagnostic metrics are never judged', () {
      MetricsDocument d(double v) => _doc({
        's@1': {
          'w': {'p50': _share(v, role: MetricRole.diagnostic)},
        },
      });
      final b = Baseline.fromLaunches([
        for (var i = 0; i < 5; i++) d(0.1),
      ], label: 'b');
      final v = judge(d(0.9), b);
      expect(v.judgements, isEmpty);
      expect(v.exitCode, 0);
    });

    test('lower delivery is the regression', () {
      const hi = Metric(
        0.98,
        kind: MetricKind.ratio,
        role: MetricRole.headline,
      );
      const lo = Metric(0.6, kind: MetricKind.ratio, role: MetricRole.headline);
      MetricsDocument d(Metric m) => _doc({
        's@1': {
          'w': {'ramp.delivery': m},
        },
      });
      final b = Baseline.fromLaunches([
        for (var i = 0; i < 5; i++) d(hi),
      ], label: 'b');
      expect(judge(d(lo), b).exitCode, 1);
      expect(judge(d(hi), b).exitCode, 0);
    });

    test('no baseline is seeded, not failed', () {
      final v = judge(_one(0.9), null);
      expect(v.state, VerdictState.seeded);
      expect(v.exitCode, 0);
    });

    test('a scenario version mismatch is stale, not compared', () {
      final v = judge(_one(0.9, id: 'scroll.drag_slow@2'), base);
      expect(v.stale, ['scroll.drag_slow@2']);
      expect(v.judgements, isEmpty);
      expect(v.exitCode, 0);
    });

    test('a corpus version mismatch makes every scenario stale', () {
      final v = judge(_one(0.9, corpus: 2), base);
      expect(v.stale, ['scroll.drag_slow@1']);
      expect(v.exitCode, 0);
    });

    test('a scenario absent from the baseline is new, not failed', () {
      final v = judge(_one(0.9, id: 'nav.jump_near@1'), base);
      expect(v.newScenarios, ['nav.jump_near@1']);
      expect(v.exitCode, 0);
    });
  });

  group('targets', () {
    test('a breach is a finding and never changes the exit status', () {
      final base = _baseline([0.7, 0.7, 0.7, 0.7, 0.7]);
      final v = judge(_one(0.7), base);
      expect(v.findings.single, contains('raster_p99_share'));
      expect(v.exitCode, 0);
    });

    test('findings are reported when there is no baseline too', () {
      expect(judge(_one(0.7), null).findings, hasLength(1));
      expect(judge(_one(0.1), null).findings, isEmpty);
    });
  });

  group('combination', () {
    test('records what it got and refuses to compare', () {
      final v = judge(
        _doc({
          's@1': {
            'w': {'raster_p99_share': _share(0.9)},
          },
        }, backend: 'skia'),
        _baseline([0.2, 0.2, 0.2, 0.2, 0.2]),
        requested: const Requested(backend: 'impeller', semantics: 'off'),
      );
      expect(v.state, VerdictState.refused);
      expect(v.refusals.single, contains('skia'));
      expect(v.exitCode, 0);
    });

    test('refresh expectation', () {
      final p = combinationProblems(
        _one(0.1).meta,
        const Requested(backend: 'impeller', semantics: 'off', refreshHz: 60),
      );
      expect(p.single, contains('120'));
    });

    test('launches that disagree are refused', () {
      expect(launchDisagreement([_one(0.1), _doc({}, hz: 60)]), isNotEmpty);
      expect(launchDisagreement([_one(0.1), _one(0.2)]), isEmpty);
    });
  });

  group('promote', () {
    test('refuses fewer than 5 launches', () {
      final c = Baseline.fromLaunches([_one(0.1), _one(0.1)], label: 'c');
      expect(promoteProblems(c, 'why').single, contains('5'));
    });

    test('refuses discarded launches', () {
      final c = _baseline([0.1, 0.1, 0.1, 0.1, 0.1], discarded: 1);
      expect(promoteProblems(c, 'why').single, contains('discarded'));
    });

    test('requires a one-line reason', () {
      final c = _baseline([0.1, 0.1, 0.1, 0.1, 0.1]);
      expect(promoteProblems(c, ' '), isNotEmpty);
      expect(promoteProblems(c, 'a\nb'), isNotEmpty);
      expect(promoteProblems(c, 'new corpus'), isEmpty);
    });

    test('the reason is stored in the promoted file', () {
      final c = _baseline([0.1, 0.1, 0.1, 0.1, 0.1]);
      expect(c.withReason('new corpus').toJson()['reason'], 'new corpus');
    });

    test('diff lists headline metrics against the current baseline', () {
      final cur = _baseline([0.2, 0.2, 0.2, 0.2, 0.2]);
      final next = _baseline([0.3, 0.3, 0.3, 0.3, 0.3]);
      final text = headlineDiff(cur, next);
      expect(text, contains('scroll.drag_slow@1'));
      expect(text, contains('20.0%'));
      expect(text, contains('30.0%'));
      expect(headlineDiff(null, next), contains('new'));
    });
  });

  group('render', () {
    test('names regressions and states', () {
      final base = _baseline([0.2, 0.2, 0.2, 0.2, 0.2]);
      expect(renderVerdict(judge(_one(0.5), base)), contains('REGRESSED'));
      expect(renderVerdict(judge(_one(0.5), null)), contains('seeded'));
      expect(
        renderVerdict(judge(_one(0.5, id: 'scroll.drag_slow@3'), base)),
        contains('stale, not compared'),
      );
    });
  });
}
