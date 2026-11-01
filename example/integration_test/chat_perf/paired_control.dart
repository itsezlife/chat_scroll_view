/// The paired-control bookkeeping the synthetic and the real keyboard contexts
/// share: where the last measured window ended, the control that replays its
/// gesture without the inset change, and the seats both start from.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';

import 'device_context.dart';
import 'keyboard_ramp.dart';
import 'scenarios/keyboard_scenarios.dart';

/// [KeyboardContext.control] and [KeyboardContext.seat] over a chat whose
/// [rampController] and [rampPad] the context samples.
base mixin PairedControl on DeviceContext {
  ChatScrollController get rampController;
  ValueListenable<double> get rampPad;

  /// Brings the keyboard down before a control run, which starts from rest.
  Future<void> restBeforeControl();

  /// Brings the keyboard down before a seat; a no-op where the scenario's
  /// own steps already leave it down.
  Future<void> restBeforeSeat();

  ({String name, RampEnd end})? _lastWindow;

  RampEnd _end() => RampEnd(
    anchorId: rampController.anchorMessageId,
    anchorOffsetDp: rampController.anchorPixelOffset,
    padDp: rampPad.value,
  );

  /// Settles after window [name] and records where it ended, for the control
  /// that may follow.
  Future<void> endRampWindow(String name) async {
    await settle();
    _lastWindow = (name: name, end: _end());
  }

  Future<void> control(Future<void> Function() body) async {
    final (:name, end: withRamp) = switch (_lastWindow) {
      final last? => last,
      null => throw StateError(
        '${scenario.key}: a control runs after a measured window',
      ),
    };
    await restBeforeControl();
    await body();
    await settle();
    windows[name]!.addAll(
      pairedControlMetrics(withRamp: withRamp, control: _end()),
    );
  }

  Future<void> seat(KeyboardSeat seat) async {
    await restBeforeSeat();
    await switch (seat) {
      KeyboardSeat.tail => jumpToNewest(),
      KeyboardSeat.midHistory => jumpTo(history ~/ 2),
    };
  }
}
