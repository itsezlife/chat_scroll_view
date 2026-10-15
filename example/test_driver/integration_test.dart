import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver_extended.dart';

import '../integration_test/panel_perf/report.dart';

/// Host-side driver for `integration_test/`: stores each scenario's report
/// under `$PERF_OUT/runs/$PERF_LABEL/<key>.json` (see [ReportStore]).
///
/// - keys ending `_timeline` hold a VM timeline (loadable in Perfetto) and are
///   written next to the reports with the derived frame summary;
/// - every other key holds a scenario report.
///
/// Reports are written on failure too: a red run is the baseline.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  onScreenshot: (name, bytes, [args]) async {
    final out = Directory('${_root()}/runs/${_label()}')
      ..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    if (data == null) return;
    final store = ReportStore(_root());
    final dir = '${_root()}/runs/${_label()}';
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      if (entry.key.endsWith('_timeline')) {
        await driver.TimelineSummary.summarize(
          driver.Timeline.fromJson(value),
        ).writeTimelineToFile(
          entry.key,
          destinationDirectory: dir,
          pretty: true,
          includeSummary: true,
        );
      } else {
        store.writeJson(_label(), entry.key, value.cast<String, Object?>());
      }
    }
  },
);

String _label() => Platform.environment['PERF_LABEL'] ?? 'device';

/// Stable report root; `tool/run_panel_perf.sh` exports the same default.
String _root() => Platform.environment['PERF_OUT'] ?? 'perf';
