import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';
import '../../integration_test/chat_perf/table.dart';

void main() {
  test('prints headline metrics per scenario window, shares as percent', () {
    const doc = MetricsDocument(
      meta: LaunchMeta(
        device: 'SM-S938B',
        os: 'Android 16',
        flutterVersion: '3',
        dartVersion: '3',
        backend: 'impeller',
        refreshRateHz: 120,
        semanticsMode: 'off',
        corpusVersion: 1,
        buildMode: 'profile',
      ),
      scenarios: {
        'scroll.drag_slow@1': {
          'drag': {
            'build_p99_share': Metric(
              0.4,
              kind: MetricKind.share,
              role: MetricRole.headline,
            ),
            'over_budget_share': Metric(
              0.0125,
              kind: MetricKind.share,
              role: MetricRole.headline,
            ),
            'frames': Metric(
              800,
              kind: MetricKind.count,
              role: MetricRole.headline,
            ),
            'budget_ms': Metric(
              8.3333,
              kind: MetricKind.ms,
              role: MetricRole.diagnostic,
            ),
          },
        },
      },
    );
    final text = renderTable(doc);
    expect(text, contains('scroll.drag_slow@1'));
    expect(text, contains('drag'));
    expect(text, contains('40.0%'));
    expect(text, contains('1.3%'));
    expect(text, contains('800'));
    expect(text, contains('120 Hz'));
    expect(text, isNot(contains('budget_ms')));
  });
}
