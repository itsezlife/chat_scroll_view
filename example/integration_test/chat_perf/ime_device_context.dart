/// The on-device [ImeContext]: drives the real system keyboard and the panel
/// over the real chat screen, and samples the same per-frame trace the
/// synthetic family does.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_composer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_context.dart';
import 'ime_comparability.dart';
import 'keyboard_ramp.dart';
import 'metrics.dart';
import 'real_chat_host.dart';
import 'registry.dart';
import 'scenarios/ime_scenarios.dart';
import 'scenarios/keyboard_scenarios.dart';

/// How long the inset and the pad must hold still to count as settled.
const _stillFor = Duration(milliseconds: 300);

/// The longest a transition may take to settle.
const _settleBound = Duration(seconds: 5);

final class DeviceImeContext extends DeviceContext implements ImeContext {
  DeviceImeContext(RealChatHost screen, Scenario scenario)
    : _screen = screen,
      super(screen, scenario) {
    screen.tester.binding.addPersistentFrameCallback(_onFrame);
    _pad = screen.pad;
    _controller = screen.controller;
  }

  /// Mounts the chat on the platform keyboard: the host reads the real IME.
  static Future<(RealChatHost, DeviceImeContext)> mount(
    WidgetTester tester,
    Scenario scenario, {
    required int history,
  }) async {
    final screen = await RealChatHost.mount(tester, history);
    return (screen, DeviceImeContext(screen, scenario));
  }

  final RealChatHost _screen;
  late final ValueListenable<double> _pad;
  late final ChatScrollController _controller;

  final _samples = <RampSample>[];
  final _clock = Stopwatch()..start();
  bool _sampling = false;
  bool _moving = false;

  /// Whether the window's signal is the pad, not the inset: a panel moves the
  /// pad with no keyboard inset.
  bool _signalIsPad = false;
  RampEnd? _windowEnd;
  String? _lastWindow;

  WidgetTester get _t => _screen.tester;

  double get _dpr => _t.view.devicePixelRatio;

  double get _insetPx => _t.view.viewInsets.bottom;

  Finder get _field => find.descendant(
    of: find.byType(ChatComposer),
    matching: find.byType(EditableText),
  );

  Finder get _panelToggle =>
      find.byKey(const ValueKey<String>(ChatComposerActions.panel));

  RampSample _read() => RampSample(
    tMs: _clock.elapsedMicroseconds / 1000,
    insetPx: _signalIsPad ? _pad.value * _dpr : _insetPx,
    padDp: _pad.value,
    anchorId: _controller.anchorMessageId,
    anchorOffsetDp: _controller.anchorPixelOffset,
  );

  // After the frame: the pad and the anchor are those the frame laid out.
  void _onFrame(Duration _) {
    if (_sampling) _samples.add(_read());
  }

  RampEnd _end() => RampEnd(
    anchorId: _controller.anchorMessageId,
    anchorOffsetDp: _controller.anchorPixelOffset,
    padDp: _pad.value,
  );

  /// Pumps frames until the signal has held still for [_stillFor].
  Future<void> _untilStill() async {
    final bound = DateTime.now().add(_settleBound);
    var last = _signalIsPad ? _pad.value * _dpr : _insetPx;
    var since = DateTime.now();
    while (DateTime.now().isBefore(bound)) {
      await _t.pump(const Duration(milliseconds: 16));
      final now = _signalIsPad ? _pad.value * _dpr : _insetPx;
      if (now != last) {
        last = now;
        since = DateTime.now();
      } else if (DateTime.now().difference(since) >= _stillFor) {
        return;
      }
    }
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
      _signalIsPad = false;
      _sampling = true;
      await body();
      _sampling = false;
    });
    final budgetMs = windows[name]!['budget_ms']!.value;
    final samples = List.of(_samples);
    // The real ramp's length is the system's: the frames it should deliver are
    // its observed duration over the vsync budget.
    final ramp = rampMetrics(samples, expectedFrames: 1);
    final durationMs = ramp['ramp.duration_ms']?.value ?? 0;
    final metrics = rampMetrics(samples, expectedFrames: durationMs / budgetMs);
    if (_moving) {
      // A moving window's anchor is the fling's: only the paired control can
      // read the engine error.
      metrics
        ..remove('engine.comp_error_dp')
        ..remove('jump.messages');
    }
    windows[name]!.addAll({
      ...metrics,
      kImeSettledInsetMetric: Metric(
        _insetPx,
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
    await closeKeyboard();
    await body();
    await settle();
    windows[name]!.addAll(
      pairedControlMetrics(withRamp: withRamp, control: _end()),
    );
  }

  @override
  Future<void> seat(KeyboardSeat seat) async {
    await switch (seat) {
      KeyboardSeat.tail => jumpToNewest(),
      KeyboardSeat.midHistory => jumpTo(history ~/ 2),
    };
  }

  @override
  Future<void> openKeyboard() async {
    await _t.tap(_field.first);
    await _untilStill();
  }

  @override
  Future<void> closeKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } on MissingPluginException {
      // No platform keyboard to command.
    }
    await _untilStill();
  }

  @override
  Future<void> openPanel() async {
    _signalIsPad = _sampling;
    await _t.tap(_panelToggle);
    await _untilStill();
    _signalIsPad = false;
  }

  @override
  Future<void> closePanel() async {
    await _t.tap(_panelToggle);
    // The toggle may bring the keyboard back; the panel is closed either way
    // once the keyboard is dismissed.
    await closeKeyboard();
  }

  @override
  Future<void> switchToPanel() async {
    await _t.tap(_panelToggle);
    await _untilStill();
  }

  @override
  Future<void> growComposer({
    required int lines,
    required Duration after,
  }) async {
    await idle(after);
    _t.widget<EditableText>(_field.first).controller.text = [
      for (var i = 0; i < lines; i++) 'line ${i + 1}',
    ].join('\n');
    await _t.pump();
  }

  @override
  Future<void> fling(double dy, Duration duration) {
    _moving = true;
    return super.fling(dy, duration);
  }
}
