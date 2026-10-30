import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'bench_host.dart';
import 'corpus.dart';
import 'device_context.dart';
import 'metrics.dart';
import 'perf_host.dart';
import 'real_chat_host.dart';
import 'registry.dart';
import 'report_document.dart';
import 'scale.dart';
import 'scenario_mounts.dart';
import 'scenarios/ime_scenarios.dart';
import 'scenarios/keyboard_scenarios.dart';
import 'scenarios/scroll_scenarios.dart';
import 'scenarios/selection_scenarios.dart';
import 'semantics.dart';

/// On-device chat viewport performance suite entry point (profile mode).
///
/// Run through `dart run tool/chat_perf.dart quick`; defines it passes:
/// `CHAT_PERF_SCENARIO` (comma-separated globs over scenario ids; empty runs
/// all), `CHAT_PERF_COLD` (`true` runs the cold scenarios, one launch each;
/// otherwise the shared-process set), `CHAT_PERF_BACKEND` (`impeller` or
/// `skia`, recorded as given), `CHAT_PERF_HISTORY` (messages in the seeded
/// history), `CHAT_PERF_SEMANTICS` (`off` by default, `on` or `pair`).
const _filter = String.fromEnvironment('CHAT_PERF_SCENARIO');
const _backend = String.fromEnvironment(
  'CHAT_PERF_BACKEND',
  defaultValue: 'impeller',
);

/// `true` runs the cold scenarios (one per launch); `false` the shared set.
const _cold = bool.fromEnvironment('CHAT_PERF_COLD');
const _history = int.fromEnvironment('CHAT_PERF_HISTORY', defaultValue: 20000);
const _semantics = String.fromEnvironment('CHAT_PERF_SEMANTICS');

/// Report keys the host driver writes as `<key>.json`.
const kMetricsKey = 'chat_perf_metrics';
const kFramesKey = 'chat_perf_frames';

/// Every registered family, in the order they run.
final allScenarios = ScenarioRegistry([
  ...scrollScenarios.all,
  ...keyboardScenarios.all,
  ...imeScenarios.all,
  ...selectionScenarios.all,
]);

Future<(PerfHost, DeviceContext)> _mountPlain(
  WidgetTester tester,
  Scenario scenario,
) async {
  final host = switch (scenario.subject) {
    ScenarioSubject.bench => await BenchHost.mount(
      tester,
      BenchCorpus(count: _history, profile: scenario.profile),
      floatingDayHeader: scenario.floatingDayHeader,
    ),
    ScenarioSubject.realChat => await RealChatHost.mount(tester, _history),
  };
  return (host, DeviceContext(host, scenario));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final run = SemanticsRun.parse(_semantics);
  var firstPassSemantics = 'off';

  // `semanticsEnabled: false` is the switch: the test binding otherwise holds
  // a semantics handle for the whole test, so the engine builds semantics
  // every frame. The `on` pass takes its own handle.
  testWidgets('chat perf scenarios', semanticsEnabled: false, (tester) async {
    final selected = allScenarios.where(_filter, cold: _cold);
    expect(selected, isNotEmpty, reason: 'no scenario matches "$_filter"');

    final scenarios = <String, Map<String, Map<String, Metric>>>{};
    final sidecar = <String, List<FrameRow>>{};
    final skipped = <String, String>{};
    for (final scenario in selected) {
      if (scenario.skipReasonOn(defaultTargetPlatform.name.toLowerCase())
          case final reason?) {
        skipped[scenario.key] = reason;
        continue;
      }
      if (scenario.historyTiers.isNotEmpty) {
        // One fresh host per tier; semantics off unless the launch asks `on`.
        final byTier = <int, Map<String, Map<String, Metric>>>{};
        for (final tier in scenario.historyTiers) {
          final handle = run == SemanticsRun.on
              ? tester.ensureSemantics()
              : null;
          final host = await BenchHost.mount(tester, BenchCorpus(count: tier));
          final ctx = DeviceContext(host, scenario);
          await scenario.run(ctx);
          await host.dispose();
          handle?.dispose();
          byTier[tier] = ctx.windows;
          for (final w in ctx.frames.entries) {
            sidecar['${scenario.key}/${w.key}.${tierLabel(tier)}'] = w.value;
          }
        }
        scenarios[scenario.key] = assembleTiers(byTier, scenario.windows);
        continue;
      }
      final byPass = <bool, DeviceContext>{};
      // A pair starts with an unrecorded off pass: the first run in a process
      // pays one-time raster costs, which would otherwise land on `off` only.
      final warmUp = run == SemanticsRun.pair;
      for (final (i, on) in [if (warmUp) false, ...run.passes].indexed) {
        final recorded = !(warmUp && i == 0);
        final handle = on ? tester.ensureSemantics() : null;
        final measured = SemanticsBinding.instance.semanticsEnabled;
        if (recorded && byPass.isEmpty) {
          firstPassSemantics = measured ? 'on' : 'off';
        }
        expect(measured, on, reason: 'semantics mode is not what was asked');
        final (host, ctx) = isKeyboardScenario(scenario)
            ? await mountKeyboardScenario(
                tester,
                scenario,
                history: _history,
              ).then((m) => (m.host, m.ctx))
            : await _mountPlain(tester, scenario);
        if (run == SemanticsRun.pair && recorded) {
          // Traced, so the timeline shows whether semantics work ran.
          final key =
              'chat_perf_${scenario.id.replaceAll('.', '_')}'
              '_sem_${on ? 'on' : 'off'}_timeline';
          await binding.traceAction(() => scenario.run(ctx), reportKey: key);
          final timeline = binding.reportData?[key];
          final events = timeline is Map<String, Object?>
              ? countSemanticsEvents(timeline)
              : -1;
          for (final w in ctx.windows.values) {
            w['semantics_events'] = Metric(
              events.toDouble(),
              kind: MetricKind.count,
              role: MetricRole.diagnostic,
            );
          }
        } else {
          await scenario.run(ctx);
        }
        await host.dispose();
        handle?.dispose();
        if (recorded) byPass[on] = ctx;
      }
      final windows = scenarios[scenario.key] = {};
      for (final w in scenario.windows) {
        final off = byPass[false]?.windows[w];
        final on = byPass[true]?.windows[w];
        if (off != null) windows[w] = off;
        if (on != null) windows[off == null ? w : '$w.sem_on'] = on;
        if (off != null && on != null) {
          windows['$w.sem_ratio'] = semanticsRatio(off: off, on: on);
        }
      }
      for (final pass in byPass.entries) {
        for (final w in pass.value.frames.entries) {
          final name = pass.key && byPass.length > 1
              ? '${w.key}.sem_on'
              : w.key;
          sidecar['${scenario.key}/$name'] = w.value;
        }
      }
    }

    final meta = LaunchMeta(
      // The runner fills the device model and Flutter version in (the app
      // cannot read either without a plugin).
      device: 'unknown',
      os: Platform.operatingSystemVersion,
      flutterVersion: 'unknown',
      dartVersion: Platform.version.split(' ').first,
      backend: _backend,
      refreshRateHz: tester.view.display.refreshRate,
      // As measured from the binding when the first pass ran.
      semanticsMode: firstPassSemantics,
      semanticsRequested: run.name,
      corpusVersion: kCorpusVersion,
      buildMode: kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
    );
    binding.reportData = {
      ...?binding.reportData,
      kMetricsKey: MetricsDocument(
        meta: meta,
        scenarios: scenarios,
        skipped: skipped,
      ).toJson(),
      kFramesKey: FrameSidecar(sidecar).toJson(),
    };
    debugPrint(
      '[chat-perf] ${kProfileMode ? 'profile' : 'NOT profile'} '
      '${selected.map((s) => s.key).join(', ')}',
    );
  });
}
