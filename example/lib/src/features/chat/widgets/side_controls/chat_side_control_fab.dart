import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_control_counter.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_control_glass.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/overshoot_curve.dart';
import 'package:flutter/material.dart';

export 'overshoot_curve.dart';

/// Frosted round side-control FAB (Telegram page-down / search up-down chrome).
///
/// Visibility (opacity + scale 0.7→1 + slide) is owned by
/// [ChatSideControlsStack] so siblings share one layout. This widget only
/// paints glass, icon, optional badge, and press scale.
class ChatSideControlFab extends StatefulWidget {
  /// Creates a glass side-control FAB.
  const ChatSideControlFab({
    required this.onTap,
    this.count = 0,
    this.flipIconY = false,
    this.semanticLabel,
    super.key,
  });

  /// Tap handler.
  final VoidCallback onTap;

  /// Optional unread / hit badge above the glass (0 hides).
  final int count;

  /// When `true`, flips the chevron (Telegram search-up).
  final bool flipIconY;

  /// Accessibility label.
  final String? semanticLabel;

  /// Painted frosted circle diameter.
  static const double glassSize = 44;

  /// Transparent hit inset around the glass (each side).
  static const double hitPadding = 6;

  /// Touch / layout box = glass + padding.
  static const double outerSize = glassSize + 2 * hitPadding;

  /// Extra frame height above the outer box for the badge slot.
  static const double counterBand = 8;

  /// Total layout height of one FAB frame.
  static const double frameHeight = outerSize + counterBand;

  /// Gap between consecutive slots when neither has a badge (Telegram `dp(10)`).
  static const double stackGap = 10;

  /// Extra gap when the slot below shows a counter (Telegram `+ dp(10)`).
  static const double stackGapWithBadge = 20;

  @override
  State<ChatSideControlFab> createState() => _ChatSideControlFabState();
}

class _ChatSideControlFabState extends State<ChatSideControlFab>
    with SingleTickerProviderStateMixin {
  static const Duration _pressInDuration = Duration(milliseconds: 80);
  static const Duration _pressOutDuration = Duration(milliseconds: 350);
  static const double _pressScaleDelta = 0.13;
  static const double _counterSlotHeight = 28;

  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: _pressInDuration);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _press
      ..duration = _pressInDuration
      ..animateTo(1, curve: Curves.linear);
  }

  void _onTapUp(TapUpDetails _) => _releasePress();

  void _onTapCancel() => _releasePress();

  void _releasePress() {
    _press
      ..duration = _pressOutDuration
      ..animateTo(0, curve: const OvershootCurve());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;
    final glassColor = colorScheme.surfaceContainerHighest;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final pressScale = 1.0 - _pressScaleDelta * _press.value;
          return Transform.scale(scale: pressScale, child: child);
        },
        // One detector for glass + badge: the counter paints above the circle
        // and would otherwise steal hits without firing [onTap].
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: SizedBox(
            width: ChatSideControlFab.outerSize,
            height: ChatSideControlFab.frameHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: ChatSideControlFab.outerSize,
                  child: Center(
                    child: ChatSideControlGlass(
                      size: ChatSideControlFab.glassSize,
                      iconColor: iconColor,
                      glassColor: glassColor,
                      flipIconY: widget.flipIconY,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _counterSlotHeight,
                  child: Align(
                    alignment: Alignment.center,
                    child: ChatSideControlCounter(count: widget.count),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
