import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';
import '../../integration_test/chat_perf/semantics.dart';
import '../../integration_test/chat_perf/table.dart';

Metric _share(double v) =>
    Metric(v, kind: MetricKind.share, role: MetricRole.headline);

void main() {
  group('SemanticsRun', () {
    test('defaults to off and parses the three modes', () {
      expect(SemanticsRun.parse(''), SemanticsRun.off);
      expect(SemanticsRun.parse('off'), SemanticsRun.off);
      expect(SemanticsRun.parse('on'), SemanticsRun.on);
      expect(SemanticsRun.parse('pair'), SemanticsRun.pair);
    });

    test('rejects anything else', () {
      expect(() => SemanticsRun.parse('maybe'), throwsFormatException);
    });

    test('passes lists the semantics states a scenario runs under', () {
      expect(SemanticsRun.off.passes, [false]);
      expect(SemanticsRun.on.passes, [true]);
      expect(SemanticsRun.pair.passes, [false, true]);
    });
  });

  group('countSemanticsEvents', () {
    test('counts semantics work events by name', () {
      final timeline = {
        'traceEvents': [
          {'name': 'Semantics.updateChildren'},
          {'name': 'ensureGeometry'},
          {'name': 'SemanticsNode.updateWith'},
          {'name': 'BUILD'},
          {'name': 'Semantics.updateChildren'},
        ],
      };
      expect(countSemanticsEvents(timeline), 4);
    });

    test('is zero without events', () {
      expect(countSemanticsEvents({'traceEvents': <Object?>[]}), 0);
      expect(countSemanticsEvents(const {}), 0);
    });
  });

  group('semanticsRatio', () {
    test('divides each shared headline metric on / off', () {
      final ratio = semanticsRatio(
        off: {'build_p99_share': _share(0.2), 'frames': _share(800)},
        on: {'build_p99_share': _share(0.3), 'frames': _share(800)},
      );
      expect(ratio['build_p99_share']!.value, closeTo(1.5, 1e-9));
      expect(ratio['build_p99_share']!.kind, MetricKind.ratio);
      expect(ratio.containsKey('frames'), isFalse);
    });

    test('skips a metric whose off value is zero', () {
      final ratio = semanticsRatio(
        off: {'over_budget_share': _share(0)},
        on: {'over_budget_share': _share(0.1)},
      );
      expect(ratio, isEmpty);
    });
  });

  test('table prints ratios with an x suffix and the requested mode', () {
    const doc = MetricsDocument(
      meta: LaunchMeta(
        device: 'd',
        os: 'o',
        flutterVersion: 'f',
        dartVersion: 'd',
        backend: 'impeller',
        refreshRateHz: 120,
        semanticsMode: 'off',
        semanticsRequested: 'pair',
        corpusVersion: 1,
        buildMode: 'profile',
      ),
      scenarios: {
        's.a@1': {
          'drag.sem_ratio': {
            'build_p99_share': Metric(
              1.5,
              kind: MetricKind.ratio,
              role: MetricRole.diagnostic,
            ),
          },
        },
      },
    );
    final text = renderTable(doc);
    expect(text, contains('1.50x'));
    expect(text, contains('requested pair'));
  });

  test('metadata round-trips the requested mode, defaulting to off', () {
    final json = const LaunchMeta(
      device: 'd',
      os: 'o',
      flutterVersion: 'f',
      dartVersion: 'd',
      backend: 'impeller',
      refreshRateHz: 60,
      semanticsMode: 'on',
      semanticsRequested: 'on',
      corpusVersion: 1,
      buildMode: 'profile',
    ).toJson();
    expect(LaunchMeta.fromJson(json).semanticsRequested, 'on');
    json.remove('semanticsRequested');
    expect(LaunchMeta.fromJson(json).semanticsRequested, 'off');
  });
}
