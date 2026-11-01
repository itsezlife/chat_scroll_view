/// The on-device [KeyboardContext]: drives the synthetic keyboard over the real
/// chat screen and samples the ramp every frame.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_context.dart';
import 'keyboard_ramp.dart';
import 'metrics.dart';
import 'paired_control.dart';
import 'real_chat_host.dart';
import 'registry.dart';
import 'scenarios/keyboard_scenarios.dart';
import 'synthetic_soft_keyboard.dart';

final class DeviceKeyboardContext extends DeviceContext
    with PairedControl
    implements KeyboardContext {
  DeviceKeyboardContext(
    RealChatHost screen,
    this.keyboard,
    Scenario scenario,
    this.profile, {
    required this.overrideReachedPad,
  }) : _screen = screen,
       super(screen, scenario) {
    screen.tester.binding.addPersistentFrameCallback(_onFrame);
    rampPad = screen.pad;
    rampController = screen.controller;
  }

  /// Mounts the chat on a synthetic keyboard and checks whether a `viewInsets`
  /// override alone reaches the host's pad.
  static Future<(RealChatHost, DeviceKeyboardContext)> mount(
    WidgetTester tester,
    Scenario scenario,
    InsetCurveProfile profile, {
    required int history,
  }) async {
    final keyboard = SyntheticSoftKeyboard();
    final screen = await RealChatHost.mount(
      tester,
      history,
      softKeyboard: keyboard,
    );
    // The host reads its keyboard from the port, so this is expected to be
    // false; it is measured, not assumed.
    await tester.pump(const Duration(milliseconds: 100));
    final before = screen.pad.value;
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final reached = (screen.pad.value - before).abs() > 1;
    tester.view.resetViewInsets();
    await tester.pump(const Duration(milliseconds: 300));
    return (
      screen,
      DeviceKeyboardContext(
        screen,
        keyboard,
        scenario,
        profile,
        overrideReachedPad: reached,
      ),
    );
  }

  final RealChatHost _screen;
  @override
  late final ValueListenable<double> rampPad;
  @override
  late final ChatScrollController rampController;
  final SyntheticSoftKeyboard keyboard;
  final InsetCurveProfile profile;

  /// Whether a `viewInsets` override alone moved the host's pad (recorded on
  /// every window as a diagnostic).
  final bool overrideReachedPad;

  final _samples = <RampSample>[];
  final _clock = Stopwatch()..start();
  bool _sampling = false;
  bool _moving = false;
  double _rampMs = 0;

  WidgetTester get _t => _screen.tester;

  double get _dpr => _t.view.devicePixelRatio;

  RampSample _read() => RampSample(
    tMs: _clock.elapsedMicroseconds / 1000,
    insetPx: keyboard.heightDp * _dpr,
    padDp: rampPad.value,
    anchorId: rampController.anchorMessageId,
    anchorOffsetDp: rampController.anchorPixelOffset,
  );

  // After the frame: the pad and the anchor are those the frame laid out.
  void _onFrame(Duration _) {
    if (_sampling) _samples.add(_read());
  }

  @override
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  }) async {
    await super.measure(name, primer: primer, () async {
      _samples.clear();
      _moving = false;
      _rampMs = 0;
      _sampling = true;
      await body();
      _sampling = false;
    });
    final window = windows[name]!;
    final budgetMs = window['budget_ms']!.value;
    final metrics = rampMetrics(
      List.of(_samples),
      expectedFrames: _rampMs / budgetMs,
    );
    if (_moving) {
      // A moving window's anchor is the fling's: only the paired control can
      // read the engine error.
      metrics
        ..remove(kCompErrorMetric)
        ..remove('jump.messages');
    }
    window.addAll({
      ...metrics,
      'inset_override.reached_pad': Metric(
        overrideReachedPad ? 1 : 0,
        kind: MetricKind.count,
        role: MetricRole.diagnostic,
      ),
    });
    await endRampWindow(name);
  }

  // The previous run left the keyboard up; a control or a seat starts from
  // rest.
  @override
  Future<void> restBeforeControl() async => keyboard.rest(0);

  @override
  Future<void> restBeforeSeat() async => keyboard.rest(0);

  @override
  Future<void> ramp(InsetCurve curve) async {
    if (_sampling) {
      _rampMs += curve.durationMs;
      // The frame before the first write is the trace's origin.
      _samples.add(_read());
    }
    final clock = Stopwatch()..start();
    while (clock.elapsedMicroseconds / 1000 < curve.durationMs) {
      keyboard.move(
        curve.at(clock.elapsedMicroseconds / 1000) * profile.heightDp,
      );
      await _t.pump();
    }
    keyboard.rest(curve.at(curve.durationMs) * profile.heightDp);
    await _t.pump();
  }

  @override
  Future<void> fling(double dy, Duration duration) {
    _moving = true;
    return super.fling(dy, duration);
  }

  @override
  Future<void> handOffToPanel(InsetCurve curve) async {
    await _t.tap(find.byKey(const ValueKey<String>(ChatComposerActions.panel)));
    await ramp(curve);
  }
}
