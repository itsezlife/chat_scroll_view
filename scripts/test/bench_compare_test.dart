import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

BenchReport report(Map<String, BenchMetric> metrics, {String suite = 's'}) =>
    BenchReport(suite: suite, metrics: metrics);

BenchMetric ratio(double v) => BenchMetric(BenchMetricKind.ratio, v);
BenchMetric count(double v) => BenchMetric(BenchMetricKind.count, v);
BenchMetric rate(double v) => BenchMetric(BenchMetricKind.rate, v);

void main() {
  group('BenchReport', () {
    test('round-trips through json', () {
      final original = report({
        'layout.ssl.64': ratio(0.25),
        'attached.64': count(8),
        'hit.stickers': rate(0.9),
      });

      final copy = BenchReport.fromJson(original.toJson());

      expect(copy.suite, 's');
      expect(copy.metrics.keys, unorderedEquals(original.metrics.keys));
      expect(copy.metrics['layout.ssl.64']!.kind, BenchMetricKind.ratio);
      expect(copy.metrics['hit.stickers']!.value, 0.9);
    });

    test('rejects a schema it does not know', () {
      expect(
        () => BenchReport.fromJson(const {
          'schema': 99,
          'suite': 's',
          'metrics': {},
        }),
        throwsFormatException,
      );
    });

    test('rejects a metric of an unknown kind', () {
      expect(
        () => BenchReport.fromJson(const {
          'schema': 1,
          'suite': 's',
          'metrics': {
            'x': {'kind': 'bogus', 'value': 1},
          },
        }),
        throwsFormatException,
      );
    });

    test('median of runs takes the middle value of every metric', () {
      final merged = BenchReport.medianOf([
        report({'a': ratio(1), 'b': count(8)}),
        report({'a': ratio(5), 'b': count(8)}),
        report({'a': ratio(2), 'b': count(8)}),
      ]);

      expect(merged.metrics['a']!.value, 2.0);
      expect(merged.metrics['b']!.value, 8);
    });

    test('median of an even number of runs averages the middle pair', () {
      final merged = BenchReport.medianOf([
        report({'a': ratio(1)}),
        report({'a': ratio(3)}),
      ]);

      expect(merged.metrics['a']!.value, 2.0);
    });

    test('median keeps only metrics every run produced', () {
      final merged = BenchReport.medianOf([
        report({'a': ratio(1), 'only_first': ratio(1)}),
        report({'a': ratio(1)}),
      ]);

      expect(merged.metrics.keys, ['a']);
    });

    test('median of nothing is an error, not an empty report', () {
      expect(() => BenchReport.medianOf(const []), throwsArgumentError);
    });

    test('regressed() worsens every metric by the factor', () {
      final worse = report({
        'r': ratio(1),
        'c': count(10),
        'h': rate(0.8),
      }).regressed(2);

      expect(worse.metrics['r']!.value, 2.0);
      expect(worse.metrics['c']!.value, 20);
      // A rate is better when higher: worse is lower.
      expect(worse.metrics['h']!.value, closeTo(0.4, 1e-9));
    });
  });

  group('BenchComparison', () {
    const tolerance = BenchTolerance.standard;

    BenchStatus statusOf(BenchMetric baseline, BenchMetric current) =>
        BenchComparison.compare(
          baseline: report({'k': baseline}),
          current: report({'k': current}),
          tolerance: tolerance,
        ).findings.single.status;

    test('a ratio inside the tolerance is ok', () {
      expect(statusOf(ratio(1), ratio(1.4)), BenchStatus.ok);
      expect(statusOf(ratio(1), ratio(0.7)), BenchStatus.ok);
    });

    test('a ratio above the tolerance regressed', () {
      expect(statusOf(ratio(1), ratio(1.6)), BenchStatus.regressed);
    });

    test('a ratio below the tolerance improved and is not a regression', () {
      expect(statusOf(ratio(1), ratio(0.4)), BenchStatus.improved);
    });

    test('a count regresses on growth only', () {
      expect(statusOf(count(100), count(104)), BenchStatus.ok);
      expect(statusOf(count(100), count(110)), BenchStatus.regressed);
      expect(statusOf(count(100), count(50)), BenchStatus.improved);
    });

    test('a rate regresses when it falls by more than the tolerance', () {
      expect(statusOf(rate(0.9), rate(0.89)), BenchStatus.ok);
      expect(statusOf(rate(0.9), rate(0.8)), BenchStatus.regressed);
      expect(statusOf(rate(0.9), rate(1)), BenchStatus.improved);
    });

    test('a zero baseline count regresses on any growth', () {
      expect(statusOf(count(0), count(0)), BenchStatus.ok);
      expect(statusOf(count(0), count(1)), BenchStatus.regressed);
    });

    test('a metric only in the current run is added, not a regression', () {
      final comparison = BenchComparison.compare(
        baseline: report({}),
        current: report({'k': ratio(1)}),
        tolerance: tolerance,
      );

      expect(comparison.findings.single.status, BenchStatus.added);
      expect(comparison.hasRegression, isFalse);
    });

    test(
      'a metric only in the baseline is missing and counts as a regression',
      () {
        // A probe that stops reporting must not silently leave the watch list.
        final comparison = BenchComparison.compare(
          baseline: report({'k': ratio(1)}),
          current: report({}),
          tolerance: tolerance,
        );

        expect(comparison.findings.single.status, BenchStatus.missing);
        expect(comparison.hasRegression, isTrue);
      },
    );

    test('a forced 2x regression of a whole report is detected', () {
      final baseline = report({
        'r': ratio(0.3),
        'c': count(169),
        'h': rate(0.95),
      });

      final comparison = BenchComparison.compare(
        baseline: baseline,
        current: baseline.regressed(2),
        tolerance: tolerance,
      );

      expect(comparison.regressions, hasLength(3));
    });

    test('markdown lists regressions first, with both values', () {
      final comparison = BenchComparison.compare(
        baseline: report({'fine': ratio(1), 'slow': ratio(1)}),
        current: report({'fine': ratio(1), 'slow': ratio(2)}),
        tolerance: tolerance,
      );

      final text = comparison.toMarkdown();

      expect(text, contains('1 regression'));
      expect(text.indexOf('slow'), lessThan(text.indexOf('fine')));
      expect(text, contains('1.00'));
      expect(text, contains('2.00'));
    });
  });
}
