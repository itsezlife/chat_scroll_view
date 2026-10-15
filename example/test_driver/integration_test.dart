import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver for `integration_test/`: writes each scenario's report to
/// `$PERF_OUT` (default `build/perf`) as `<PERF_LABEL>-<key>.json`.
///
/// - keys ending `_timeline` hold a VM timeline (loadable in Perfetto) and are
///   written with the derived frame summary;
/// - every other key holds already-summarised `FrameTiming` data.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final label = Platform.environment['PERF_LABEL'] ?? 'device';
    final out = Directory(Platform.environment['PERF_OUT'] ?? 'build/perf')
      ..createSync(recursive: true);
    File('${out.path}/$label-$name.png').writeAsBytesSync(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    if (data == null) return;
    final label = Platform.environment['PERF_LABEL'] ?? 'device';
    final out = Directory(Platform.environment['PERF_OUT'] ?? 'build/perf')
      ..createSync(recursive: true);
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      if (entry.key.endsWith('_timeline')) {
        await driver.TimelineSummary.summarize(
          driver.Timeline.fromJson(value),
        ).writeTimelineToFile(
          '$label-${entry.key}',
          destinationDirectory: out.path,
          pretty: true,
          includeSummary: true,
        );
      } else {
        File(
          '${out.path}/$label-${entry.key}.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
      }
    }
  },
);
