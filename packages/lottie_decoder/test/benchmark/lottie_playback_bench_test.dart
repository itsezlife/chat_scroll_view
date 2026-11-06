import 'package:flutter_test/flutter_test.dart';

import 'playback_bench_report.dart';

BenchReport _report(Map<String, (MetricKind, double)> metrics) => BenchReport({
  for (final e in metrics.entries) e.key: BenchMetric(e.value.$1, e.value.$2),
});

Drift _drift(BenchReport current, BenchReport baseline, String key) =>
    current.compareTo(baseline).singleWhere((c) => c.key == key).drift;

void main() {
  group('BenchReport.compareTo', () {
    final baseline = _report({
      'tick': (MetricKind.milliseconds, 2.0),
      'bytes': (MetricKind.count, 1000),
      'gone': (MetricKind.ratio, 1.0),
    });

    test('a timing within 50 percent of the baseline is the same', () {
      final current = _report({'tick': (MetricKind.milliseconds, 2.9)});
      expect(_drift(current, baseline, 'tick'), Drift.same);
    });

    test('a timing over 50 percent above the baseline is worse', () {
      final current = _report({'tick': (MetricKind.milliseconds, 3.2)});
      expect(_drift(current, baseline, 'tick'), Drift.worse);
    });

    test('a timing under two thirds of the baseline is better', () {
      final current = _report({'tick': (MetricKind.milliseconds, 1.0)});
      expect(_drift(current, baseline, 'tick'), Drift.better);
    });

    test('a count is held to 5 percent', () {
      expect(
        _drift(_report({'bytes': (MetricKind.count, 1049)}), baseline, 'bytes'),
        Drift.same,
      );
      expect(
        _drift(_report({'bytes': (MetricKind.count, 1060)}), baseline, 'bytes'),
        Drift.worse,
      );
    });

    test('a metric the run no longer reports is missing, a new one added', () {
      final current = _report({'fresh': (MetricKind.ratio, 1)});
      expect(_drift(current, baseline, 'gone'), Drift.missing);
      expect(_drift(current, baseline, 'fresh'), Drift.added);
    });

    test('a baseline of zero is the same only at zero', () {
      final zero = _report({'bytes': (MetricKind.count, 0)});
      expect(_drift(zero, zero, 'bytes'), Drift.same);
      expect(
        _drift(_report({'bytes': (MetricKind.count, 1)}), zero, 'bytes'),
        Drift.worse,
      );
    });

    test('survives a trip through json', () {
      final decoded = BenchReport.fromJson(baseline.toJson());
      expect(decoded.compareTo(baseline).map((c) => c.drift).toSet(), {
        Drift.same,
      });
    });
  });
}
