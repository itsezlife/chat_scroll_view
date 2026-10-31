import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/registry.dart';
import '../../integration_test/chat_perf/report_document.dart';
import '../../integration_test/chat_perf/trace_counts.dart';
import '../../tool/chat_perf/baseline.dart';
import '../../tool/chat_perf/build_fingerprint.dart';
import '../../tool/chat_perf/verdict.dart';

Map<String, Object?> _ev(String name, int ts, [String ph = 'B']) => {
  'name': name,
  'ph': ph,
  'ts': ts,
};

Map<String, Object?> _timeline(List<Map<String, Object?>> events) => {
  'traceEvents': events,
};

String _s(String section) => 'chat_scroll_view.$section';

Scenario _scenario(String id, {bool det = false, int tiers = 0}) => Scenario(
  id: id,
  version: 1,
  windows: const ['w'],
  run: (_) async {},
  deterministic: det,
  historyTiers: [for (var i = 0; i < tiers; i++) 100 * (i + 1)],
);

void main() {
  group('traceCounts', () {
    test('counts the sections inside each window only', () {
      final counts = traceCounts(
        _timeline([
          _ev(_s('child.build'), 5), // before any window
          _ev(traceWindowMark('fling', start: true), 10, 'i'),
          _ev(_s('layout.mode'), 11),
          _ev(_s('layout.fanOut'), 12),
          _ev(_s('child.build'), 13),
          _ev(_s('child.build'), 14),
          _ev(_s('layout.mode'), 20),
          _ev(_s('layout.fanOut'), 21),
          _ev(_s('layout.fanOut'), 22),
          _ev(traceWindowMark('fling', start: false), 30, 'i'),
          _ev(_s('layout.mode'), 40), // after the window
        ]),
      );
      expect(counts.keys, ['fling']);
      double v(String m) => counts['fling']![m]!.value;
      expect(v('trace.layout_passes'), 2);
      expect(v('trace.fan_out_passes'), 3);
      expect(v('trace.children_built'), 2);
    });

    test('ignores end events and unrelated names', () {
      final counts = traceCounts(
        _timeline([
          _ev(traceWindowMark('w', start: true), 0, 'i'),
          _ev(_s('layout.mode'), 1),
          _ev(_s('layout.mode'), 2, 'E'),
          _ev('Semantics.updateChildren', 3),
          _ev(traceWindowMark('w', start: false), 9, 'i'),
        ]),
      );
      expect(counts['w']!['trace.layout_passes']!.value, 1);
    });

    test('metrics are headline counts so the verdict judges them', () {
      final counts = traceCounts(
        _timeline([
          _ev(traceWindowMark('w', start: true), 0, 'i'),
          _ev(traceWindowMark('w', start: false), 9, 'i'),
        ]),
      );
      for (final m in counts['w']!.values) {
        expect(m.kind, MetricKind.count);
        expect(m.role, MetricRole.headline);
      }
      expect(counts['w']!['trace.layout_passes']!.value, 0);
    });

    test('an unclosed window ends at the last event', () {
      final counts = traceCounts(
        _timeline([
          _ev(traceWindowMark('w', start: true), 0, 'i'),
          _ev(_s('layout.mode'), 1),
        ]),
      );
      expect(counts['w']!['trace.layout_passes']!.value, 1);
    });
  });

  group('passes', () {
    test('trace metrics belong to the traced pass, the rest to timing', () {
      expect(passOf('trace.layout_passes'), MetricPass.traced);
      expect(passOf('raster_p99_share'), MetricPass.timing);
    });

    test('the traced document holds trace metrics only', () {
      final doc = tracedDocument(
        meta: _meta(),
        counts: {
          'scroll.fling@1': {
            'fling': {
              'trace.layout_passes': const Metric(
                4,
                kind: MetricKind.count,
                role: MetricRole.headline,
              ),
            },
          },
        },
      );
      for (final w in doc.scenarios.values.expand((s) => s.values)) {
        expect(w.keys.every((k) => passOf(k) == MetricPass.traced), isTrue);
      }
    });

    test('a traced launch never supplies timing metrics', () {
      const timing = Metric(
        0.5,
        kind: MetricKind.share,
        role: MetricRole.headline,
      );
      expect(
        () => tracedDocument(
          meta: _meta(),
          counts: {
            's@1': {
              'w': {'raster_p99_share': timing},
            },
          },
        ),
        throwsArgumentError,
      );
    });

    test('the report marks the pass that produced a metric', () {
      final base = Baseline.fromLaunches([
        _docWith(10),
        _docWith(10),
      ], label: 'b');
      final text = renderVerdict(judge(_docWith(10), base));
      expect(text, contains('trace.layout_passes [traced]'));
      expect(text, isNot(contains('raster_p99_share [traced]')));
    });
  });

  group('verdict on counts', () {
    Baseline base() => Baseline.fromLaunches([
      _docWith(100),
      _docWith(100),
      _docWith(100),
    ], label: 'b');

    test('equal counts are inside the spread', () {
      expect(judge(_docWith(100), base()).exitCode, 0);
    });

    test('one pass of drift is inside the near-exact tolerance', () {
      expect(judge(_docWith(101), base()).exitCode, 0);
    });

    test('a doubled layout count is a regression', () {
      final v = judge(_docWith(200), base());
      expect(v.exitCode, 1);
      expect(
        v.judgements.singleWhere((j) => j.regressed).metric,
        'trace.layout_passes',
      );
    });

    test('a count regresses at a few percent, not the timing margin', () {
      expect(judge(_docWith(110), base()).exitCode, 1);
    });
  });

  group('merge', () {
    test('counts join the timing windows without replacing timing', () {
      final merged = withTracedCounts(
        _docWith(1, count: false),
        _docWith(7, timing: false),
      );
      final w = merged.scenarios['s@1']!['w']!;
      expect(w['trace.layout_passes']!.value, 7);
      expect(w['raster_p99_share']!.value, 0.2);
    });
  });

  group('baseline counts', () {
    test('counts join a timing baseline and keep its timing spread', () {
      final timing = Baseline.fromLaunches([
        _docWith(0, count: false),
        _docWith(0, count: false),
      ], label: 'b');
      final counts = Baseline.fromLaunches([
        _docWith(7, timing: false),
        _docWith(8, timing: false),
      ], label: 'c');
      final w = timing.withMetricsOf(counts).scenarios['s@1']!['w']!;
      expect(w['trace.layout_passes']!.max, 8);
      expect(w['raster_p99_share']!.median, 0.2);
    });
  });

  group('selection', () {
    test('only deterministic scenarios without tiers are traced', () {
      expect(_scenario('a.b', det: true).traced, isTrue);
      expect(_scenario('a.c').traced, isFalse);
      expect(_scenario('a.d', det: true, tiers: 2).traced, isFalse);
    });

    test('report keys end in _timeline and carry no dots', () {
      expect(traceReportKey('scroll.fling_long'), endsWith('_timeline'));
      expect(traceReportKey('scroll.fling_long'), isNot(contains('.')));
    });
  });

  group('build', () {
    test('the traced define set differs from the timing set', () {
      final timing = buildDefines(backend: 'impeller');
      final traced = buildDefines(backend: 'impeller', traced: true);
      expect(timing.any((d) => d.contains('trace')), isFalse);
      expect(traced, contains('chat_scroll_view.trace=phase'));
      expect(traced, contains('CHAT_PERF_TRACED=true'));
      expect(
        buildFingerprint({
          'a': [1],
        }, traced),
        isNot(
          buildFingerprint({
            'a': [1],
          }, timing),
        ),
      );
    });
  });
}

LaunchMeta _meta() => const LaunchMeta(
  device: 'SM-S938B',
  os: 'Android 16',
  flutterVersion: '3',
  dartVersion: '3',
  backend: 'impeller',
  refreshRateHz: 120,
  semanticsMode: 'off',
  corpusVersion: 1,
  buildMode: 'profile',
);

MetricsDocument _docWith(
  double layoutPasses, {
  bool count = true,
  bool timing = true,
}) => MetricsDocument(
  meta: _meta(),
  scenarios: {
    's@1': {
      'w': {
        if (count)
          'trace.layout_passes': Metric(
            layoutPasses,
            kind: MetricKind.count,
            role: MetricRole.headline,
          ),
        if (timing)
          'raster_p99_share': const Metric(
            0.2,
            kind: MetricKind.share,
            role: MetricRole.headline,
          ),
      },
    },
  },
);
