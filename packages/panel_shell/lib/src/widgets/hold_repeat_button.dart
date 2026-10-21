import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// A control that triggers once on tap and keeps triggering while held, the
/// way a keyboard repeats a key.
///
/// - Pointer up before [initialRepeatDelay] triggers once; a cancelled pointer
///   (a scroll took the gesture) triggers nothing.
/// - Holding past it triggers on every tick, each tick arriving sooner than
///   the last by [repeatAcceleration] down to [minRepeatInterval].
/// - Enter or Space on the focused control triggers once.
///
/// The press scale comes from [ScalePressable]. This widget owns the pointer
/// lifecycle itself so the tap and the repeats cannot both fire for one press.
/// It plays no haptics: the host reacts to the event the trigger publishes.
class HoldRepeatButton extends StatefulWidget {
  /// Wraps [child] as a hold-to-repeat control that calls [onTrigger].
  const HoldRepeatButton({
    required this.onTrigger,
    required this.semanticLabel,
    required this.child,
    super.key,
  });

  /// Called for the tap and for every repeat.
  final VoidCallback onTrigger;

  /// The spoken name of the control.
  final String semanticLabel;

  /// The painted control.
  final Widget child;

  /// How long to hold before the first repeat.
  static const Duration initialRepeatDelay = Duration(milliseconds: 350);

  /// The shortest interval between repeats.
  static const Duration minRepeatInterval = Duration(milliseconds: 50);

  /// How much sooner each repeat comes than the one before.
  static const Duration repeatAcceleration = Duration(milliseconds: 100);

  @override
  State<HoldRepeatButton> createState() => _HoldRepeatButtonState();
}

class _HoldRepeatButtonState extends State<HoldRepeatButton> {
  var _pressed = false;
  var _repeated = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    _pressed = true;
    _repeated = false;
    _scheduleRepeat(HoldRepeatButton.initialRepeatDelay);
  }

  void _onUp(PointerUpEvent event) {
    final tapped = _pressed && !_repeated;
    _release();
    if (tapped) widget.onTrigger();
  }

  void _release() {
    _pressed = false;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleRepeat(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (!_pressed || !mounted) return;
      _repeated = true;
      widget.onTrigger();
      final next = Duration(
        milliseconds: (delay - HoldRepeatButton.repeatAcceleration)
            .inMilliseconds
            .clamp(
              HoldRepeatButton.minRepeatInterval.inMilliseconds,
              HoldRepeatButton.initialRepeatDelay.inMilliseconds,
            ),
      );
      _scheduleRepeat(next);
    });
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.semanticLabel,
    onTap: widget.onTrigger,
    excludeSemantics: true,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTrigger();
            return null;
          },
        ),
      },
      child: Listener(
        onPointerDown: _onDown,
        onPointerUp: _onUp,
        onPointerCancel: (_) => _release(),
        child: ScalePressable(onPressed: () {}, child: widget.child),
      ),
    ),
  );
}
