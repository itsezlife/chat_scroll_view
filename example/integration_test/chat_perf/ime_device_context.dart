/// The on-device [ImeContext]: drives the real system keyboard and the panel
/// over the real chat screen, and samples the same per-frame trace the
/// synthetic family does.
library;

import 'package:chat_composer/chat_composer.dart' show ComposerController;
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
import 'paired_control.dart';
import 'real_chat_host.dart';
import 'registry.dart';
import 'scenarios/ime_scenarios.dart';

/// How long the inset and the pad must hold still to count as settled.
const _stillFor = Duration(milliseconds: 300);

/// The longest a transition may take to settle.
const _settleBound = Duration(seconds: 5);

final class DeviceImeContext extends DeviceContext
    with PairedControl
    implements ImeContext {
  DeviceImeContext(RealChatHost screen, Scenario scenario)
    : _screen = screen,
      super(screen, scenario) {
    screen.tester.binding.addPersistentFrameCallback(_onFrame);
    rampPad = screen.pad;
    rampController = screen.controller;
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
  @override
  late final ValueListenable<double> rampPad;
  @override
  late final ChatScrollController rampController;

  final _samples = <RampSample>[];
  final _clock = Stopwatch()..start();
  bool _sampling = false;
  bool _moving = false;

  /// Whether the window's signal is the pad, not the inset: a panel moves the
  /// pad with no keyboard inset.
  bool _signalIsPad = false;

  WidgetTester get _t => _screen.tester;

  double get _dpr => _t.view.devicePixelRatio;

  double get _insetPx => _t.view.viewInsets.bottom;

  ComposerController get _composer =>
      _t.widget<ChatComposer>(find.byType(ChatComposer)).input.composer;

  /// The composer's field, found by the focus node it holds: the editable is
  /// a leaf package's type, not Flutter's `EditableText`.
  Finder get _field => find.descendant(
    of: find.byType(ChatComposer),
    matching: find.byWidgetPredicate(
      (w) => switch (w) {
        Focus(:final focusNode) => focusNode == _composer.focusNode,
        _ => false,
      },
    ),
  );

  Finder get _panelToggle =>
      find.byKey(const ValueKey<String>(ChatComposerActions.panel));

  RampSample _read() => RampSample(
    tMs: _clock.elapsedMicroseconds / 1000,
    insetPx: _signalIsPad ? rampPad.value * _dpr : _insetPx,
    padDp: rampPad.value,
    anchorId: rampController.anchorMessageId,
    anchorOffsetDp: rampController.anchorPixelOffset,
  );

  // After the frame: the pad and the anchor are those the frame laid out.
  void _onFrame(Duration _) {
    if (_sampling) _samples.add(_read());
  }

  /// Pumps frames until the signal has held still for [_stillFor].
  Future<void> _untilStill() async {
    final bound = DateTime.now().add(_settleBound);
    var last = _signalIsPad ? rampPad.value * _dpr : _insetPx;
    var since = DateTime.now();
    while (DateTime.now().isBefore(bound)) {
      await _t.pump(const Duration(milliseconds: 16));
      final now = _signalIsPad ? rampPad.value * _dpr : _insetPx;
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
    final window = windows[name]!;
    final budgetMs = window['budget_ms']!.value;
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
        ..remove(kCompErrorMetric)
        ..remove('jump.messages');
    }
    window.addAll({
      ...metrics,
      kImeSettledInsetMetric: Metric(
        _insetPx,
        kind: MetricKind.count,
        role: MetricRole.diagnostic,
      ),
    });
    await endRampWindow(name);
  }

  // The previous run left the keyboard up; the control starts from rest.
  @override
  Future<void> restBeforeControl() => closeKeyboard();

  // Every scenario seats with the keyboard down already.
  @override
  Future<void> restBeforeSeat() async {}

  @override
  Future<void> openKeyboard({Future<void> Function()? meanwhile}) async {
    await _t.tap(_field.first);
    await meanwhile?.call();
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
    // The toggle hands the panel's slot to the keyboard: wait for it to rise
    // (a hide sent before that is a no-op), then dismiss it and wait for the
    // pad to come back down.
    final bound = DateTime.now().add(const Duration(seconds: 2));
    while (_insetPx == 0 && DateTime.now().isBefore(bound)) {
      await _t.pump(const Duration(milliseconds: 16));
    }
    await closeKeyboard();
    _signalIsPad = true;
    await _untilStill();
    _signalIsPad = false;
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
    _composer
      ..clear()
      ..insertText(
        [for (var i = 0; i < lines; i++) 'line ${i + 1}'].join('\n'),
      );
    await _t.pump();
  }

  @override
  Future<void> fling(double dy, Duration duration) {
    _moving = true;
    return super.fling(dy, duration);
  }
}
