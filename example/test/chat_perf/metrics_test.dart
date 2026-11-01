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

  group('splitFirstFrames', () {
    test('splits at the span from the first frame start', () {
      final starts = <double>[1000, 1010, 1100, 1149.9, 1150, 1400];
      final (head, tail) = splitFirstFrames(
        ['a', 'b', 'c', 'd', 'e', 'f'],
        starts,
        spanMs: 150,
      );
      expect(head, ['a', 'b', 'c', 'd']);
      expect(tail, ['e', 'f']);
    });
    test('empty input splits to two empty lists', () {
      final (head, tail) = splitFirstFrames(<int>[], <double>[], spanMs: 150);
      expect(head, isEmpty);
      expect(tail, isEmpty);
    });
  });

  group('windowMetrics', () {
    // 10 frames at 120 Hz: the first two are slow (20 ms build).
    final head = [
      for (var i = 0; i < 2; i++) const FrameSample(buildMs: 20, rasterMs: 2),
    ];
    final tail = [
      for (var i = 0; i < 8; i++) const FrameSample(buildMs: 2, rasterMs: 2),
    ];

    test('headline percentiles exclude the first frames', () {
      final m = windowMetrics(head, tail, refreshRateHz: 120, cold: false);
      expect(m['frames']!.value, 8);
      expect(m['build_p99_share']!.value, closeTo(2 / 8.33333, 1e-4));
    });
    test('first frames are diagnostic for a steady scenario', () {
      final m = windowMetrics(head, tail, refreshRateHz: 120, cold: false);
      expect(m['first_frames.build_p99_share']!.value, closeTo(2.4, 1e-3));
      expect(m['first_frames.frames']!.value, 2);
      for (final e in m.entries.where((e) => e.key.startsWith('first_'))) {
        expect(e.value.role, MetricRole.diagnostic);
      }
    });
    test('first frames are headline for a cold scenario', () {
      final m = windowMetrics(head, tail, refreshRateHz: 120, cold: true);
      for (final k in [
        'first_frames.build_p99_share',
        'first_frames.raster_p99_share',
        'first_frames.over_budget_share',
        'first_frames.frames',
      ]) {
        expect(m[k]!.role, MetricRole.headline, reason: k);
      }
    });
    test('no first frames reports only their zero count', () {
      final m = windowMetrics([], tail, refreshRateHz: 120, cold: false);
      expect(m['first_frames.frames']!.value, 0);
      expect(m.containsKey('first_frames.build_p99_share'), isFalse);
    });
    test('counts frames over three budgets in the whole window', () {
      // 20 ms > 3 x 8.33 ms is false; 26 ms build and 25.1 ms raster are over.
      final m = windowMetrics(
        [...head, const FrameSample(buildMs: 26, rasterMs: 1)],
        [...tail, const FrameSample(buildMs: 1, rasterMs: 25.1)],
        refreshRateHz: 120,
        cold: false,
      );
      final over = m[kFramesOver3xBudgetMetric]!;
      expect(over.value, 2);
      expect((over.kind, over.role), (MetricKind.count, MetricRole.diagnostic));
      expect(
        windowMetrics(
          head,
          tail,
          refreshRateHz: 120,
          cold: false,
        )[kFramesOver3xBudgetMetric]!.value,
        0,
      );
    });
  });
}
