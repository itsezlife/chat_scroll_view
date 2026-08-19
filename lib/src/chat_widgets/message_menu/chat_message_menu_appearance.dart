import 'package:flutter/material.dart';

/// Enter duration.
const Duration kChatMessageMenuEnterDuration = Duration(milliseconds: 180);

/// Leave duration (~220ms).
const Duration kChatMessageMenuLeaveDuration = Duration(milliseconds: 220);

/// Leave slide distance.
const double kChatMessageMenuLeaveSlide = 5;

/// Enter scale start.
const double kChatMessageMenuEnterScale = 0.95;

/// Message-menu enter/leave around the reactions + actions column.
class ChatMessageMenuAppearance extends StatefulWidget {
  /// Creates an appearance wrapper.
  const ChatMessageMenuAppearance({
    required this.fitsAbove,
    required this.child,
    super.key,
  });

  /// Whether the menu sits above the message (leave slides up).
  final bool fitsAbove;

  /// Menu column.
  final Widget child;

  @override
  State<ChatMessageMenuAppearance> createState() =>
      ChatMessageMenuAppearanceState();
}

/// State exposing [dismiss] for coordinated leave.
class ChatMessageMenuAppearanceState extends State<ChatMessageMenuAppearance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  var _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kChatMessageMenuEnterDuration,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scale = Tween<double>(begin: kChatMessageMenuEnterScale, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Plays leave animation, then completes.
  Future<void> dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _controller.duration = kChatMessageMenuLeaveDuration;
    await _controller.reverse();
  }

  double get _leaveDy {
    if (!_leaving) return 0;
    final t = 1 - _controller.value;
    return t *
        (widget.fitsAbove
            ? -kChatMessageMenuLeaveSlide
            : kChatMessageMenuLeaveSlide);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: _opacity.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, _leaveDy),
        child: Transform.scale(
          scale: _leaving ? 1.0 : _scale.value,
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
    ),
    child: widget.child,
  );
}
