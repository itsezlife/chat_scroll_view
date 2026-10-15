import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/panel_perf/acceptance.dart';
import '../../integration_test/panel_perf/frame_metrics.dart';
import '../../integration_test/panel_perf/report.dart';

ScenarioReport _report(
  String name, {
  required List<FrameSample> samples,
  bool asserted = true,
  FlingCoverage? coverage,
}) {
  final stats = FrameStats.of(samples, budgetMs: 8.333);
  return ScenarioReport(
    scenario: name,
    asserted: asserted,
    meta: const {'refreshRateHz': 120.0, 'platform': 'android'},
    samples: samples,
    stats: stats,
    verdict: judge(stats, coverage: coverage),
    coverage: coverage,
  );
}

const _clean = FrameSample(buildMs: 1, rasterMs: 1, totalMs: 4);
const _janky = FrameSample(buildMs: 1, rasterMs: 68, totalMs: 70);

void main() {
  group('ScenarioReport', () {
    test('json carries the per-frame series and the summary', () {
      final json = _report(
        'cold_first_pass',
        samples: [_clean, _clean, _janky],
      ).toJson();

      final frames = json['frames']! as Map<String, Object?>;
      expect(frames['rasterMs'], [1.0, 1.0, 68.0]);
      expect(frames['buildMs'], [1.0, 1.0, 1.0]);
      expect(frames['totalMs'], [4.0, 4.0, 70.0]);

      final summary = json['summary']! as Map<String, Object?>;
      expect(summary['frames'], 3);
      expect(summary['overBudgetFrames'], 1);
      expect((summary['rasterMs']! as Map)['max'], 68.0);
    });

    test('json records the verdict with its reasons', () {
      final json = _report('x', samples: [_clean, _janky]).toJson();
      final verdict = json['verdict']! as Map<String, Object?>;
      expect(verdict['passed'], isFalse);
      expect(verdict['failures'], isNotEmpty);
    });

    test('json survives encode and decode into a summary', () {
      final json = _report(
        'cold_first_pass',
        samples: [_clean, _janky],
      ).toJson();
      final back = ReportSummary.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(back.scenario, 'cold_first_pass');
      expect(back.asserted, isTrue);
      expect(back.passed, isFalse);
      expect(back.frames, 2);
      expect(back.overBudgetFrames, 1);
      expect(back.rasterMaxMs, 68.0);
    });

    test('an informational scenario is marked as not asserted', () {
      final json = _report(
        'warm_pass2',
        samples: [_clean],
        asserted: false,
      ).toJson();
      expect(json['asserted'], isFalse);
    });
  });

  group('ReportStore', () {
    late Directory root;
    late ReportStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('panel_perf_store_');
      store = ReportStore(root.path);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('writes one file per scenario under the run label', () {
      store.write('s25-launch1', _report('panel_open', samples: [_clean]));
      expect(
        File('${root.path}/runs/s25-launch1/panel_open.json').existsSync(),
        isTrue,
      );
    });

    test('stores json a device handed over as it came, readable back', () {
      store.writeJson(
        'dev',
        'panel_open',
        _report('panel_open', samples: [_clean]).toJson(),
      );
      expect(store.readRun('dev').single.scenario, 'panel_open');
    });

    test('reads a run back as summaries', () {
      store
        ..write('r', _report('panel_open', samples: [_clean]))
        ..write('r', _report('cold_first_pass', samples: [_clean, _janky]));
      final run = store.readRun('r');
      expect(run.map((s) => s.scenario), ['cold_first_pass', 'panel_open']);
    });

    test('an unknown run reads as empty rather than throwing', () {
      expect(store.readRun('missing'), isEmpty);
    });

    test('a run passes only when every asserted scenario passed', () {
      store
        ..write('ok', _report('panel_open', samples: [_clean]))
        ..write('ok', _report('cold_first_pass', samples: [_clean]));
      expect(runPassed(store.readRun('ok')), isTrue);

      store
        ..write('bad', _report('panel_open', samples: [_clean]))
        ..write('bad', _report('cold_first_pass', samples: [_janky]));
      expect(runPassed(store.readRun('bad')), isFalse);
    });

    test('an informational failure does not fail the run', () {
      store
        ..write('r', _report('panel_open', samples: [_clean]))
        ..write('r', _report('cold_first_pass', samples: [_clean]))
        ..write('r', _report('warm_pass2', samples: [_janky], asserted: false));
      expect(runPassed(store.readRun('r')), isTrue);
    });

    test('a run missing a required scenario does not pass', () {
      store.write('r', _report('panel_open', samples: [_clean]));
      expect(runPassed(store.readRun('r')), isFalse);
      expect(runPassed(const []), isFalse);
    });

    test('promoting a run replaces the whole baseline set', () {
      store
        ..write('old', _report('panel_open', samples: [_janky]))
        ..write('old', _report('stale_only', samples: [_janky]))
        ..promoteBaseline('old')
        ..write('new', _report('panel_open', samples: [_clean]))
        ..promoteBaseline('new');
      final baseline = store.readBaseline();
      expect(baseline.map((s) => s.scenario), ['panel_open']);
      expect(baseline.single.overBudgetFrames, 0);
    });

    test('promoting a missing or empty run is refused', () {
      expect(() => store.promoteBaseline('missing'), throwsStateError);
    });

    test('the baseline survives later runs untouched', () {
      store
        ..write('a', _report('panel_open', samples: [_janky]))
        ..promoteBaseline('a')
        ..write('b', _report('panel_open', samples: [_clean]));
      expect(store.readBaseline().single.overBudgetFrames, 1);
    });
  });
}
