import 'dart:async';

import 'package:chat_chrome/src/motion/scale_pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Trailing backspace control with hold-to-repeat.
///
/// **Behavior**
/// - Pointer up before the first repeat → one [onBackspace] (tap).
/// - Hold past [initialRepeatDelay] → repeats, accelerating by
///   [repeatAcceleration] each tick down to [minRepeatInterval]
///   (`postBackspaceRunnable` / `Math.max(50, time - 100)`).
///
/// Visual press scale comes from [ScalePressable]; this widget owns the
/// pointer lifecycle so [ScalePressable.onPressed] is not used for delete.
class BackspaceActionButton extends StatefulWidget {
  /// Creates the backspace action cell.
  const BackspaceActionButton({
    required this.onBackspace,
    required this.child,
    super.key,
  });

  /// Deletes one grapheme / code unit at the caret (host-defined).
  final VoidCallback onBackspace;

  /// Painted icon (already sized for the action slot).
  final Widget child;

  /// Delay before the first repeat (`postBackspaceRunnable(350)`).
  static const Duration initialRepeatDelay = Duration(milliseconds: 350);

  /// Floor for the accelerating repeat interval.
  static const Duration minRepeatInterval = Duration(milliseconds: 50);

  /// Subtracted from the current delay after each repeat tick.
  static const Duration repeatAcceleration = Duration(milliseconds: 100);

  @override
  State<BackspaceActionButton> createState() => _BackspaceActionButtonState();
}

class _BackspaceActionButtonState extends State<BackspaceActionButton> {
  var _pressed = false;
  var _repeatFired = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pressed = true;
    _repeatFired = false;
    _scheduleRepeat(BackspaceActionButton.initialRepeatDelay);
  }

  void _onPointerUp(PointerUpEvent event) {
    _finishPress();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishPress();
  }

  void _finishPress() {
    _pressed = false;
    _timer?.cancel();
    _timer = null;
    if (!_repeatFired) {
      _fireBackspace();
    }
  }

  void _scheduleRepeat(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (!_pressed || !mounted) return;
      _repeatFired = true;
      _fireBackspace();
      final nextMs = (delay.inMilliseconds -
              BackspaceActionButton.repeatAcceleration.inMilliseconds)
          .clamp(
            BackspaceActionButton.minRepeatInterval.inMilliseconds,
            BackspaceActionButton.initialRepeatDelay.inMilliseconds,
          );
      _scheduleRepeat(Duration(milliseconds: nextMs));
    });
  }

  void _fireBackspace() {
    HapticFeedback.selectionClick();
    widget.onBackspace();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: ScalePressable(
        onPressed: () {},
        child: widget.child,
      ),
    );
  }
}
