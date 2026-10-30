/// Which host a scenario runs on, and how it is mounted and torn down.
library;

import 'package:flutter_test/flutter_test.dart';

import 'bench_host.dart';
import 'chat_screen_host.dart';
import 'corpus.dart';
import 'device_context.dart';
import 'keyboard_device_context.dart';
import 'keyboard_ramp.dart';
import 'registry.dart';
import 'scenarios/keyboard_scenarios.dart';

/// A mounted scenario: its context and the teardown that follows it.
typedef MountedScenario = ({
  DeviceContext ctx,
  Future<void> Function() dispose,
});

/// Mounts [scenario] on its own host: the keyboard family on the real chat
/// screen, every other on the bench host over [history] messages.
Future<MountedScenario> mountScenario(
  WidgetTester tester,
  Scenario scenario, {
  required int history,
}) async {
  if (keyboardScenarios.all.any((s) => s.id == scenario.id)) {
    final screen = await ChatScreenHost.mount(tester, history);
    final reached = await screen.insetOverrideReachesPad();
    return (
      ctx: DeviceKeyboardContext(
        screen,
        scenario,
        InsetCurveProfile.androidRamp,
        overrideReachedPad: reached,
      ),
      dispose: screen.dispose,
    );
  }
  final host = await BenchHost.mount(tester, BenchCorpus(count: history));
  return (ctx: DeviceContext(host, scenario), dispose: host.dispose);
}
