/// How a scenario's host is mounted: the keyboard family needs the real chat
/// screen over a synthetic keyboard, every other scenario a plain host.
library;

import 'package:flutter_test/flutter_test.dart';

import 'device_context.dart';
import 'keyboard_device_context.dart';
import 'keyboard_ramp.dart';
import 'perf_host.dart';
import 'registry.dart';
import 'scenarios/keyboard_scenarios.dart';

/// A mounted scenario: its host and its context.
typedef MountedScenario = ({PerfHost host, DeviceContext ctx});

/// Whether [scenario] belongs to the keyboard family.
bool isKeyboardScenario(Scenario scenario) =>
    keyboardScenarios.all.any((s) => s.id == scenario.id);

/// Mounts the keyboard-family [scenario] on the real chat screen.
Future<MountedScenario> mountKeyboardScenario(
  WidgetTester tester,
  Scenario scenario, {
  required int history,
}) async {
  final (host, ctx) = await DeviceKeyboardContext.mount(
    tester,
    scenario,
    InsetCurveProfile.androidRamp,
    history: history,
  );
  return (host: host, ctx: ctx);
}
