import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The card's enter and leave.
///
/// It fades in over the `menuEnter` role. [SelectionMenuAppearanceState.dismiss]
/// plays the leave: the `menuLeave` role's fade, and a drift of
/// [SelectionMenuMetrics.leaveDrift] away from the selection (up when the card
/// is [fitsAbove], down when it is below), both following the controller's
/// value on its way back to zero. Only the menu's own closing goes through
/// here; a tap outside the field, a text change or a rotation unmount the card
/// at once, and a scroll fades it through the editable's toolbar wrapper
/// without involving this widget.
class SelectionMenuAppearance extends StatefulWidget {
  /// Wraps [child] in the enter and leave.
  const SelectionMenuAppearance({
    required this.fitsAbove,
    required this.motion,
    required this.child,
    super.key,
  });

  /// Whether the card is above the selection, which turns the leave's drift
  /// up.
  final bool fitsAbove;

  /// The roles and speed of the fade.
  final ChromeMotionData motion;

  /// The card.
  final Widget child;

  @override
  State<SelectionMenuAppearance> createState() =>
      SelectionMenuAppearanceState();
}

/// The state of a [SelectionMenuAppearance]; call [dismiss] to play the leave.
class SelectionMenuAppearanceState extends State<SelectionMenuAppearance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    final enter = widget.motion.specOf(MotionRole.menuEnter);
    final leave = widget.motion.specOf(MotionRole.menuLeave);
    _controller = AnimationController(vsync: this, duration: enter.duration);
    // The reverse curve is applied to the controller's value as it falls, not
    // flipped in time: ease-in then starts the fade slowly and ends it fast.
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: enter.curve,
      reverseCurve: leave.curve,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Plays the leave and completes when it has. Once only.
  Future<void> dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _controller.duration = widget.motion.durationOf(MotionRole.menuLeave);
    await _controller.reverse();
  }

  double get _drift {
    if (!_leaving) return 0;
    final away = (1 - _controller.value) * SelectionMenuMetrics.leaveDrift;
    return widget.fitsAbove ? -away : away;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: _opacity.value,
      child: Transform.translate(offset: Offset(0, _drift), child: child),
    ),
    child: widget.child,
  );
}
