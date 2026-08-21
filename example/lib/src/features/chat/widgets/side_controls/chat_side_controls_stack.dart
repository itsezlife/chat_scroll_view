import 'dart:ui' as ui;

import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_control_fab.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One slot in [ChatSideControlsStack] (bottom → top order).
@immutable
class ChatSideControlSlot {
  /// Creates a stack slot.
  const ChatSideControlSlot({
    required this.visible,
    required this.child,
    // Telegram accumulates `dp(44)` (glass), not the full chrome frame —
    // badge / hit padding may overlap the next slot (`Clip.none`).
    this.height = ChatSideControlFab.glassSize,
    this.gap,
  });

  /// When `false`, the slot animates out and frees space for siblings.
  final bool visible;

  /// Control chrome (typically [ChatSideControlFab]).
  final Widget child;

  /// Layout height used for stacking (Telegram: glass diameter `44`).
  final double height;

  /// Override stack gap after this slot; defaults to [ChatSideControlsStack.gap].
  final double? gap;
}

/// Telegram-style side-controls column: siblings share one visibility layout.
///
/// Each frame, visible fraction `t` contributes `(height + gap) * t` to the
/// stack height. Translation is `slideAway * (1 - t) - heightBelow`, so when
/// one button hides the others slide into place together (search up/down +
/// page-down).
class ChatSideControlsStack extends StatefulWidget {
  /// Creates a side-controls stack.
  const ChatSideControlsStack({
    required this.slots,
    this.bottomInset,
    this.right = 12,
    this.gap = ChatSideControlFab.stackGap,
    this.slideAway = 80,
    this.hiddenScale = 0.7,
    this.duration = const Duration(milliseconds: 280),
    super.key,
  });

  /// Bottom → top (page-down first, then search-down, then search-up).
  final List<ChatSideControlSlot> slots;

  /// Composer / keyboard inset (same as page-down FAB).
  final ValueListenable<double>? bottomInset;

  /// Distance from the right edge.
  final double right;

  /// Extra gap between consecutive visible slots.
  final double gap;

  /// Slide distance when a slot is fully hidden (Telegram `dp(80)`).
  final double slideAway;

  /// Scale at visibility `0` (Telegram `0.7`).
  final double hiddenScale;

  /// Show/hide animation duration.
  final Duration duration;

  @override
  State<ChatSideControlsStack> createState() => _ChatSideControlsStackState();
}

class _ChatSideControlsStackState extends State<ChatSideControlsStack>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final slot in widget.slots)
        AnimationController(
          vsync: this,
          duration: widget.duration,
          value: slot.visible ? 1.0 : 0.0,
        ),
    ];
  }

  @override
  void didUpdateWidget(covariant ChatSideControlsStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcileControllers();
    for (var i = 0; i < widget.slots.length; i++) {
      final target = widget.slots[i].visible ? 1.0 : 0.0;
      final c = _controllers[i];
      if ((c.value - target).abs() < 0.001 && !c.isAnimating) continue;
      c.animateTo(target, duration: widget.duration, curve: Curves.decelerate);
    }
  }

  void _reconcileControllers() {
    final n = widget.slots.length;
    if (_controllers.length == n) return;
    // Grow / shrink controller list when slot count changes.
    while (_controllers.length > n) {
      _controllers.removeLast().dispose();
    }
    while (_controllers.length < n) {
      final i = _controllers.length;
      final visible = widget.slots[i].visible;
      _controllers.add(
        AnimationController(
          vsync: this,
          duration: widget.duration,
          value: visible ? 1.0 : 0.0,
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = widget.bottomInset;
    final stack = ListenableBuilder(
      listenable: Listenable.merge(_controllers),
      builder: (context, _) => _buildStack(),
    );
    return Positioned(
      right: widget.right,
      bottom: 0,
      child: inset == null
          ? stack
          : ValueListenableBuilder<double>(
              valueListenable: inset,
              child: stack,
              builder: (context, value, child) => Padding(
                padding: EdgeInsets.only(bottom: value),
                child: child,
              ),
            ),
    );
  }

  Widget _buildStack() {
    // Mirror Telegram: accumulate height from bottom slot upward.
    var totalHeight = 0.0;
    final layers = <Widget>[];
    for (var i = 0; i < widget.slots.length; i++) {
      final slot = widget.slots[i];
      final t = _controllers[i].value;
      final heightBelow = totalHeight;
      final gap = slot.gap ?? widget.gap;
      totalHeight += (slot.height + gap) * t;

      final scale = ui.lerpDouble(widget.hiddenScale, 1.0, t)!;
      layers.add(
        Positioned(
          right: 0,
          bottom: heightBelow,
          child: IgnorePointer(
            ignoring: t < 0.01,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, widget.slideAway * (1 - t)),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: slot.child,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final stackHeight = totalHeight < 1 ? 1.0 : totalHeight;
    return SizedBox(
      width: ChatSideControlFab.outerSize,
      height: stackHeight,
      child: Stack(clipBehavior: Clip.none, children: layers),
    );
  }
}
