import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/panel_perf/frame_metrics.dart';

void main() {
  group('budgetShare', () {
    test('is the time over the vsync budget', () {
      expect(budgetShare(4.1666667, vsyncBudgetMs(120)), closeTo(0.5, 1e-6));
    });
    test('exceeds one for a frame over budget', () {
      expect(budgetShare(16.6666667, vsyncBudgetMs(120)), closeTo(2, 1e-6));
    });
  });

  group('headlineMetrics', () {
    // 100 frames at 120 Hz (budget 8.3333 ms): frame i builds in i * 0.05 ms;
    // raster is 2 ms except the last five frames, which take 10 ms.
    final samples = [
      for (var i = 1; i <= 100; i++)
        FrameSample(buildMs: i * 0.05, rasterMs: i > 95 ? 10 : 2),
    ];
    final metrics = headlineMetrics(samples, refreshRateHz: 120);

    test('build p99 is the 99th ranked build time as a budget share', () {
      // Nearest rank: 99th of 100 = 4.95 ms.
      expect(metrics['build_p99_share']!.value, closeTo(4.95 / 8.33333, 1e-4));
    });
    test('raster p99 is a budget share', () {
      expect(metrics['raster_p99_share']!.value, closeTo(10 / 8.33333, 1e-4));
    });
    test('over-budget share counts frames over one vsync', () {
      expect(metrics['over_budget_share']!.value, closeTo(0.05, 1e-9));
    });
    test('frame count is exact and the budget uses the reported rate', () {
      expect(metrics['frames']!.value, 100);
      expect(metrics['frames']!.kind, MetricKind.count);
      expect(metrics['budget_ms']!.value, closeTo(8.3333, 1e-3));
      expect(metrics['budget_ms']!.role, MetricRole.diagnostic);
    });
    test('headline metrics carry the headline role and share kind', () {
      for (final k in [
        'build_p99_share',
        'raster_p99_share',
        'over_budget_share',
      ]) {
        expect(metrics[k]!.role, MetricRole.headline);
        expect(metrics[k]!.kind, MetricKind.share);
      }
    });
    test('no frames gives zeros, not an error', () {
      final empty = headlineMetrics(const [], refreshRateHz: 120);
      expect(empty['frames']!.value, 0);
      expect(empty['over_budget_share']!.value, 0);
    });
  });
}
