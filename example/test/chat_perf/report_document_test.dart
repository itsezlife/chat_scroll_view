import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/report_document.dart';

void main() {
  const meta = LaunchMeta(
    device: 'SM-S938B',
    os: 'Android 16',
    flutterVersion: '3.x',
    dartVersion: '3.y',
    backend: 'impeller',
    refreshRateHz: 120,
    semanticsMode: 'on',
    corpusVersion: 1,
  );

  const doc = MetricsDocument(
    meta: meta,
    scenarios: {
      'scroll.drag_slow@1': {
        'drag': {
          'frames': Metric(
            10,
            kind: MetricKind.count,
            role: MetricRole.headline,
          ),
        },
      },
    },
  );

  test('is versioned and keeps the metadata block', () {
    final json = doc.toJson();
    expect(json['schema'], kMetricsSchemaVersion);
    expect((json['meta']! as Map)['refreshRateHz'], 120);
    expect((json['meta']! as Map)['semanticsMode'], 'on');
    expect((json['meta']! as Map)['corpusVersion'], 1);
  });

  test('keys metrics by scenario id@version, then window, then name', () {
    final json = doc.toJson();
    final metric =
        (((json['scenarios']! as Map)['scroll.drag_slow@1']! as Map)['drag']!
            as Map)['frames'];
    expect(metric, {'value': 10.0, 'kind': 'count', 'role': 'headline'});
  });

  test('round trips', () {
    final back = MetricsDocument.fromJson(doc.toJson());
    expect(back.scenarios['scroll.drag_slow@1']!['drag']!['frames']!.value, 10);
    expect(back.meta.device, 'SM-S938B');
  });

  test('per-frame arrays are not part of the metrics document', () {
    expect(doc.toJson().containsKey('frames'), isFalse);
  });
}
