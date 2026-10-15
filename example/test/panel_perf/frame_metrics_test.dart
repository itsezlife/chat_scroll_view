import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/panel_perf/frame_metrics.dart';

void main() {
  group('vsyncBudgetMs', () {
    test('is one over the refresh rate', () {
      expect(vsyncBudgetMs(120), closeTo(8.333, 0.001));
      expect(vsyncBudgetMs(60), closeTo(16.667, 0.001));
    });

    test('falls back to 60 Hz when the display reports no rate', () {
      expect(vsyncBudgetMs(0), closeTo(16.667, 0.001));
      expect(vsyncBudgetMs(double.nan), closeTo(16.667, 0.001));
    });
  });

  group('percentile', () {
    final hundred = [for (var i = 1; i <= 100; i++) i.toDouble()];

    test('uses nearest rank, so p99 of 1..100 is 99', () {
      expect(percentile(hundred, 0.99), 99);
      expect(percentile(hundred, 0.5), 50);
      expect(percentile(hundred, 1), 100);
    });

    test('does not need sorted input', () {
      expect(percentile([5, 1, 9, 3], 0.5), 3);
    });

    test('one outlier among 455 frames is above p99', () {
      final frames = [for (var i = 0; i < 454; i++) 1.0, 68.0];
      expect(percentile(frames, 0.99), 1);
      expect(percentile(frames, 1), 68);
    });

    test('empty input has no percentile', () {
      expect(() => percentile(const [], 0.5), throwsArgumentError);
    });
  });

  group('FrameStats', () {
    const budget = 8.0;

    test('counts a frame over budget when build or raster exceeds it', () {
      final stats = FrameStats.of(const [
        FrameSample(buildMs: 1, rasterMs: 1),
        FrameSample(buildMs: 9, rasterMs: 1),
        FrameSample(buildMs: 1, rasterMs: 9),
        FrameSample(buildMs: 8, rasterMs: 8), // exactly on budget is fine
      ], budgetMs: budget);
      expect(stats.frames, 4);
      expect(stats.overBudgetFrames, 2);
    });

    test('counts frames over twice the budget as severe', () {
      final stats = FrameStats.of(const [
        FrameSample(buildMs: 1, rasterMs: 17),
        FrameSample(buildMs: 1, rasterMs: 16),
      ], budgetMs: budget);
      expect(stats.overBudgetFrames, 2);
      expect(stats.severeFrames, 1);
    });

    test('raster percentiles and max come from raster time only', () {
      final stats = FrameStats.of([
        for (var i = 1; i <= 100; i++)
          FrameSample(buildMs: 50, rasterMs: i.toDouble()),
      ], budgetMs: budget);
      expect(stats.rasterP99Ms, 99);
      expect(stats.rasterMaxMs, 100);
      expect(stats.buildP99Ms, 50);
    });

    test('no frames gives empty stats rather than a throw', () {
      final stats = FrameStats.of(const [], budgetMs: budget);
      expect(stats.frames, 0);
      expect(stats.overBudgetFrames, 0);
      expect(stats.rasterP99Ms, 0);
    });
  });
}
