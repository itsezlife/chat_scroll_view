import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';
import '../../integration_test/chat_perf/scale.dart';
import '../../integration_test/chat_perf/scenarios/scroll_scenarios.dart';
import '../../integration_test/chat_perf/table.dart';

Metric _share(double v) =>
    Metric(v, kind: MetricKind.share, role: MetricRole.headline);

void main() {
  test('tier labels', () {
    expect([for (final t in kScaleTiers) tierLabel(t)], ['1k', '20k', '200k']);
  });

  test('the scale family runs at the three tiers', () {
    final scale = scrollScenarios.all.where((s) => s.id.startsWith('scale.'));
    expect(scale.map((s) => s.id), [
      'scale.fling',
      'scale.jump_far',
      'scale.animate_far',
    ]);
    for (final s in scale) {
      expect(s.historyTiers, [1000, 20000, 200000]);
    }
  });

  test('ratioMetrics divides other by base and skips zero bases', () {
    final r = ratioMetrics(
      base: {'a': _share(0.2), 'b': _share(0), 'c': _share(1)},
      other: {'a': _share(0.6), 'b': _share(1), 'd': _share(1)},
      names: ['a', 'b', 'c', 'd'],
    );
    expect(r.keys, ['a']);
    expect(r['a']!.value, closeTo(3, 1e-9));
    expect(r['a']!.kind, MetricKind.ratio);
  });

  test('assembleTiers names tier windows and ratios against the first', () {
    final windows = assembleTiers(
      {
        1000: {
          'fling': {'build_p99_share': _share(0.1)},
        },
        20000: {
          'fling': {'build_p99_share': _share(0.2)},
        },
        200000: {
          'fling': {'build_p99_share': _share(0.5)},
        },
      },
      ['fling'],
    );
    expect(windows.keys, [
      'fling.1k',
      'fling.20k',
      'fling.ratio_20k',
      'fling.200k',
      'fling.ratio_200k',
    ]);
    expect(
      windows['fling.ratio_200k']!['build_p99_share']!.value,
      closeTo(5, 1e-9),
    );
  });

  test('the report table prints scale ratios', () {
    final doc = MetricsDocument(
      meta: const LaunchMeta(
        device: 'd',
        os: 'o',
        flutterVersion: 'f',
        dartVersion: 'd',
        backend: 'impeller',
        refreshRateHz: 120,
        semanticsMode: 'off',
        corpusVersion: 1,
      ),
      scenarios: {
        'scale.fling@1': assembleTiers(
          {
            1000: {
              'fling': {'build_p99_share': _share(0.1)},
            },
            20000: {
              'fling': {'build_p99_share': _share(0.3)},
            },
          },
          ['fling'],
        ),
      },
    );
    expect(renderTable(doc), contains('3.00x'));
    final back = MetricsDocument.fromJson(doc.toJson());
    expect(
      back
          .scenarios['scale.fling@1']!['fling.ratio_20k']!['build_p99_share']!
          .kind,
      MetricKind.ratio,
    );
  });
}
