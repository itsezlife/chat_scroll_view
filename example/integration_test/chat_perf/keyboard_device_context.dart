/// The on-device [KeyboardContext]: drives the synthetic keyboard over the real
/// chat screen and samples the ramp every frame.
library;

import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_screen_host.dart';
import 'device_context.dart';
import 'keyboard_ramp.dart';
import 'metrics.dart';
import 'registry.dart';
import 'scenarios/keyboard_scenarios.dart';

final class DeviceKeyboardContext extends DeviceContext
    implements KeyboardContext {
  DeviceKeyboardContext(
    this.screen,
    Scenario scenario,
    this.profile, {
    required this.overrideReachedPad,
  }) : super.over(screen.tester, screen.viewport, scenario) {
    screen.tester.binding.addPersistentFrameCallback(_onFrame);
  }

  final ChatScreenHost screen;
  final InsetCurveProfile profile;

  /// Whether a `viewInsets` override alone moved the host's pad (recorded on
  /// every window as a diagnostic).
  final bool overrideReachedPad;

  final _samples = <RampSample>[];
  final _clock = Stopwatch()..start();
  bool _sampling = false;
  bool _moving = false;
  double _rampMs = 0;
  RampEnd? _windowEnd;
  String? _lastWindow;

  WidgetTester get _t => screen.tester;

  double get _dpr => _t.view.devicePixelRatio;

  RampSample _read() => RampSample(
    tMs: _clock.elapsedMicroseconds / 1000,
    insetPx: screen.keyboard.heightDp * _dpr,
    padDp: screen.pad.value,
    anchorId: screen.controller.anchorMessageId,
    anchorOffsetDp: screen.controller.anchorPixelOffset,
  );

  // After the frame: the pad and the anchor are those the frame laid out.
  void _onFrame(Duration _) {
    if (_sampling) _samples.add(_read());
  }

  RampEnd _end() => RampEnd(
    anchorId: screen.controller.anchorMessageId,
    anchorOffsetDp: screen.controller.anchorPixelOffset,
    padDp: screen.pad.value,
  );

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
    final budgetMs = windows[name]!['budget_ms']!.value;
    final metrics = rampMetrics(
      List.of(_samples),
      expectedFrames: _rampMs / budgetMs,
    );
    if (_moving) {
      // A moving window's anchor is the fling's: only the paired control can
      // read the engine error.
      metrics
        ..remove('engine.comp_error_dp')
        ..remove('jump.messages');
    }
    windows[name]!.addAll({
      ...metrics,
      'inset_override.reached_pad': Metric(
        overrideReachedPad ? 1 : 0,
        kind: MetricKind.count,
        role: MetricRole.diagnostic,
      ),
    });
    await settle();
    _windowEnd = _end();
    _lastWindow = name;
  }

  @override
  Future<void> control(Future<void> Function() body) async {
    final name = _lastWindow!;
    final withRamp = _windowEnd!;
    // The previous run left the keyboard up; the control starts from rest.
    screen.keyboard.rest(0);
    await body();
    await settle();
    windows[name]!.addAll(
      pairedControlMetrics(withRamp: withRamp, control: _end()),
    );
  }

  @override
  Future<void> seat(KeyboardSeat seat) async {
    screen.keyboard.rest(0);
    screen.controller.jumpTo(switch (seat) {
      KeyboardSeat.tail => screen.history - 1,
      KeyboardSeat.midHistory => screen.history ~/ 2,
    });
    await settle();
  }

  @override
  Future<void> ramp(InsetCurve curve) async {
    final keyboard = screen.keyboard;
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
  Future<void> fling() async {
    _moving = true;
    await _t.timedDrag(
      screen.viewport,
      const Offset(0, 600),
      const Duration(milliseconds: 90),
    );
  }

  @override
  Future<void> hold(Duration duration) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < duration) {
      await _t.pump();
    }
  }

  @override
  Future<void> handOffToPanel(InsetCurve curve) async {
    await _t.tap(find.byKey(const ValueKey<String>(ChatComposerActions.panel)));
    await ramp(curve);
  }
}
