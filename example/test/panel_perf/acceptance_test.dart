import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/panel_perf/acceptance.dart';
import '../../integration_test/panel_perf/frame_metrics.dart';

FrameStats _stats(List<FrameSample> samples, {double budgetMs = 8}) =>
    FrameStats.of(samples, budgetMs: budgetMs);

List<FrameSample> _clean(int n) =>
    List.filled(n, const FrameSample(buildMs: 1, rasterMs: 1));

const _fullCoverage = FlingCoverage(
  reachedEnd: true,
  returnedToTop: true,
  maxOffsetPx: 9000,
  viewportHeightPx: 300,
  expectedExtentPx: 9300,
);

void main() {
  group('judge', () {
    test('passes when no frame is over budget and raster p99 is low', () {
      final verdict = judge(_stats(_clean(455)));
      expect(verdict.passed, isTrue);
      expect(verdict.failures, isEmpty);
    });

    test('fails on a single frame over the vsync budget', () {
      final verdict = judge(
        _stats([..._clean(454), const FrameSample(buildMs: 1, rasterMs: 8.5)]),
      );
      expect(verdict.passed, isFalse);
      expect(verdict.failures.single, contains('1 of 455 frames'));
    });

    test('fails when raster p99 exceeds 2 ms even inside the budget', () {
      // 5 of 100 frames at 3 ms: under an 8 ms budget but p99 is 3 ms.
      final verdict = judge(
        _stats([
          ..._clean(95),
          ...List.filled(5, const FrameSample(buildMs: 1, rasterMs: 3)),
        ]),
      );
      expect(verdict.passed, isFalse);
      expect(verdict.failures.single, contains('raster p99'));
    });

    test('raster p99 of exactly 2 ms passes', () {
      final verdict = judge(
        _stats(List.filled(100, const FrameSample(buildMs: 1, rasterMs: 2))),
      );
      expect(verdict.passed, isTrue);
    });

    test('reports every failed criterion, not only the first', () {
      final verdict = judge(
        _stats([
          ..._clean(98),
          ...List.filled(2, const FrameSample(buildMs: 1, rasterMs: 60)),
        ]),
      );
      expect(verdict.failures, hasLength(2));
    });

    test('no recorded frames is a failure, never a vacuous pass', () {
      final verdict = judge(_stats(const []));
      expect(verdict.passed, isFalse);
      expect(verdict.failures.single, contains('no frames'));
    });

    test('the thresholds can be tightened by the caller', () {
      final verdict = judge(
        _stats(List.filled(100, const FrameSample(buildMs: 1, rasterMs: 2))),
        criteria: const AcceptanceCriteria(maxRasterP99Ms: 1.5),
      );
      expect(verdict.passed, isFalse);
    });

    test(
      'a clean run still fails when coverage is required and incomplete',
      () {
        final verdict = judge(
          _stats(_clean(100)),
          coverage: const FlingCoverage(
            reachedEnd: false,
            returnedToTop: true,
            maxOffsetPx: 2000,
            viewportHeightPx: 300,
            expectedExtentPx: 9300,
          ),
        );
        expect(verdict.passed, isFalse);
        expect(verdict.failures.single, contains('coverage'));
      },
    );

    test('a clean run with full coverage passes', () {
      expect(
        judge(_stats(_clean(100)), coverage: _fullCoverage).passed,
        isTrue,
      );
    });
  });

  group('FlingCoverage', () {
    test('fraction is the span the viewport showed over the content', () {
      expect(_fullCoverage.fraction, closeTo(1, 1e-9));
      const half = FlingCoverage(
        reachedEnd: false,
        returnedToTop: false,
        maxOffsetPx: 4350,
        viewportHeightPx: 300,
        expectedExtentPx: 9300,
      );
      expect(half.fraction, closeTo(0.5, 1e-9));
    });

    test('is complete only when the end and the top were both reached', () {
      expect(_fullCoverage.isComplete, isTrue);
      const noTop = FlingCoverage(
        reachedEnd: true,
        returnedToTop: false,
        maxOffsetPx: 9000,
        viewportHeightPx: 300,
        expectedExtentPx: 9300,
      );
      expect(noTop.isComplete, isFalse);
    });

    test('is incomplete when the fraction is far short of the estimate', () {
      // The stall detector said "end" but the offset only covers 60% of the
      // catalogue: the estimate and the observation disagree, so do not trust it.
      const suspicious = FlingCoverage(
        reachedEnd: true,
        returnedToTop: true,
        maxOffsetPx: 5300,
        viewportHeightPx: 300,
        expectedExtentPx: 9300,
      );
      expect(suspicious.isComplete, isFalse);
    });

    test('an unknown extent is never complete', () {
      const unknown = FlingCoverage(
        reachedEnd: true,
        returnedToTop: true,
        maxOffsetPx: 9000,
        viewportHeightPx: 300,
        expectedExtentPx: 0,
      );
      expect(unknown.isComplete, isFalse);
    });
  });

  group('estimateContentExtent', () {
    test('adds one header per section and one cell row per span of leaves', () {
      // 2 sections: 17 leaves -> 3 rows, 8 leaves -> 1 row, span 8.
      final extent = estimateContentExtent(
        leavesPerSection: const [17, 8],
        spanCount: 8,
        cellExtent: 48,
        headerExtent: 32,
      );
      expect(extent, 2 * 32 + 4 * 48);
    });

    test('an empty catalogue has no extent', () {
      expect(
        estimateContentExtent(
          leavesPerSection: const [],
          spanCount: 8,
          cellExtent: 48,
          headerExtent: 32,
        ),
        0,
      );
    });
  });
}
