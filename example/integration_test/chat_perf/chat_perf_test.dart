import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'bench_host.dart';
import 'corpus.dart';
import 'device_context.dart';
import 'metrics.dart';
import 'report_document.dart';
import 'scenarios/scroll_scenarios.dart';

/// On-device chat viewport performance suite entry point (profile mode).
///
/// Run through `dart run tool/chat_perf.dart quick`; defines it passes:
/// `CHAT_PERF_SCENARIO` (comma-separated globs over scenario ids; empty runs
/// all), `CHAT_PERF_BACKEND` (`impeller` or `skia`, recorded as given),
/// `CHAT_PERF_HISTORY` (messages in the seeded history).
const _filter = String.fromEnvironment('CHAT_PERF_SCENARIO');
const _backend = String.fromEnvironment(
  'CHAT_PERF_BACKEND',
  defaultValue: 'impeller',
);
const _history = int.fromEnvironment('CHAT_PERF_HISTORY', defaultValue: 20000);

/// Report keys the host driver writes as `<key>.json`.
const kMetricsKey = 'chat_perf_metrics';
const kFramesKey = 'chat_perf_frames';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('chat perf scenarios', (tester) async {
    final selected = scrollScenarios.where(_filter);
    expect(selected, isNotEmpty, reason: 'no scenario matches "$_filter"');

    final scenarios = <String, Map<String, Map<String, Metric>>>{};
    final sidecar = <String, List<FrameRow>>{};
    for (final scenario in selected) {
      final host = await BenchHost.mount(
        tester,
        const BenchCorpus(count: _history),
      );
      final ctx = DeviceContext(host, scenario);
      await scenario.run(ctx);
      await host.dispose();
      scenarios[scenario.key] = ctx.windows;
      for (final w in ctx.frames.entries) {
        sidecar['${scenario.key}/${w.key}'] = w.value;
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
      // As observed: whether the engine has semantics on right now.
      semanticsMode: SemanticsBinding.instance.semanticsEnabled ? 'on' : 'off',
      corpusVersion: kCorpusVersion,
    );
    binding.reportData = {
      ...?binding.reportData,
      kMetricsKey: MetricsDocument(meta: meta, scenarios: scenarios).toJson(),
      kFramesKey: FrameSidecar(sidecar).toJson(),
    };
    debugPrint(
      '[chat-perf] ${kProfileMode ? 'profile' : 'NOT profile'} '
      '${selected.map((s) => s.key).join(', ')}',
    );
  });
}
