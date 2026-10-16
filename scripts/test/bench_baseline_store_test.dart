import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

void main() {
  late Directory dir;
  late BenchBaselineStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bench_baselines');
    store = BenchBaselineStore(dir.path, platform: 'macos');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const report = BenchReport(
    suite: 'panel_catalog.semantics-off',
    metrics: {'layout.64': BenchMetric(BenchMetricKind.ratio, 0.5)},
  );

  test('a suite with no stored baseline loads as null', () {
    expect(store.load('panel_catalog.semantics-off'), isNull);
  });

  test('saves per suite and platform, and loads it back', () {
    store.save(report);

    expect(
      File('${dir.path}/panel_catalog.semantics-off.macos.json').existsSync(),
      isTrue,
    );
    final loaded = store.load('panel_catalog.semantics-off')!;
    expect(loaded.metrics['layout.64']!.value, 0.5);
  });

  test('another platform does not see the baseline', () {
    store.save(report);

    final linux = BenchBaselineStore(dir.path, platform: 'linux');

    expect(linux.load('panel_catalog.semantics-off'), isNull);
  });

  test('stored files end with a newline and keep keys sorted', () {
    store.save(
      const BenchReport(
        suite: 's',
        metrics: {
          'b': BenchMetric(BenchMetricKind.count, 2),
          'a': BenchMetric(BenchMetricKind.count, 1),
        },
      ),
    );

    final text = File('${dir.path}/s.macos.json').readAsStringSync();

    expect(text, endsWith('}\n'));
    expect(text.indexOf('"a"'), lessThan(text.indexOf('"b"')));
  });

  test('a corrupt baseline is an error, not a silent reseed', () {
    File('${dir.path}/s.macos.json').writeAsStringSync('{not json');

    expect(() => store.load('s'), throwsFormatException);
  });
}
