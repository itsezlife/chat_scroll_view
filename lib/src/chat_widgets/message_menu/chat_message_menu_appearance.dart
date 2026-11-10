import 'dart:async';

import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_presentation.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/material.dart';

/// Message-menu enter/leave around the reactions + actions column.
///
/// Plays the session's [ChatMessageMenuTransitionBuilder] when the host gives
/// one (so a host can give every menu and overlay of its chrome one motion),
/// [ChatMessageMenuDefaultTransition] otherwise.
class ChatMessageMenuAppearance extends StatefulWidget {
  /// Creates an appearance wrapper.
  const ChatMessageMenuAppearance({
    required this.presentation,
    required this.origin,
    required this.rows,
    required this.child,
    this.transitionBuilder,
    super.key,
  });

  /// How the menu is presented.
  final ChatMessageMenuPresentation presentation;

  /// The corner or edge the menu is anchored at.
  final Alignment origin;

  /// How many action rows the menu has.
  final int rows;

  /// The host's motion, or null for the package's.
  final ChatMessageMenuTransitionBuilder? transitionBuilder;

  /// Menu column.
  final Widget child;

  /// The origin of a menu whose top left is [menuOrigin], placed for a press
  /// at [tap]: the corner at the pointer for a popup, the edge facing the
  /// message (the bottom when the menu sits above it) for a sheet.
  static Alignment originFor({
    required ChatMessageMenuPresentation presentation,
    required Offset menuOrigin,
    required Offset? tap,
    required bool fitsAbove,
  }) {
    final y = fitsAbove ? 1.0 : -1.0;
    return switch (presentation) {
      ChatMessageMenuPresentation.sheet => Alignment(-1, y),
      ChatMessageMenuPresentation.popup => Alignment(
        tap != null && menuOrigin.dx < tap.dx - 0.5 ? 1 : -1,
        y,
      ),
    };
  }

  @override
  State<ChatMessageMenuAppearance> createState() =>
      ChatMessageMenuAppearanceState();
}

/// State exposing [dismiss] for coordinated leave.
class ChatMessageMenuAppearanceState extends State<ChatMessageMenuAppearance> {
  Completer<void>? _left;

  /// Plays the leave, then completes.
  Future<void> dismiss() {
    if (!mounted) return Future<void>.value();
    final left = _left;
    if (left != null) return left.future;
    final next = _left = Completer<void>();
    setState(() {});
    return next.future;
  }

  void _onHidden() {
    final left = _left;
    if (left != null && !left.isCompleted) left.complete();
  }

  @override
  void dispose() {
    _onHidden();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transition = ChatMessageMenuTransition(
      visible: _left == null,
      onHidden: _onHidden,
      presentation: widget.presentation,
      origin: widget.origin,
      rows: widget.rows,
    );
    return switch (widget.transitionBuilder) {
      final builder? => builder(context, transition, widget.child),
      null => ChatMessageMenuDefaultTransition(
        transition: transition,
        child: widget.child,
      ),
    };
  }
}

/// The package's message-menu motion: a fade and a slight scale in, a fade
/// and a 5 dp slide away from the message out.
class ChatMessageMenuDefaultTransition extends StatefulWidget {
  /// Plays [transition] on [child].
  const ChatMessageMenuDefaultTransition({
    required this.transition,
    required this.child,
    super.key,
  });

  /// Enter duration.
  static const Duration enterDuration = Duration(milliseconds: 180);

  /// Leave duration (~220ms).
  static const Duration leaveDuration = Duration(milliseconds: 220);

  /// Leave slide distance.
  static const double leaveSlide = 5;

  /// Enter scale start.
  static const double enterScale = 0.95;

  /// What to play.
  final ChatMessageMenuTransition transition;

  /// Menu column.
  final Widget child;

  @override
  State<ChatMessageMenuDefaultTransition> createState() =>
      _ChatMessageMenuDefaultTransitionState();
}

class _ChatMessageMenuDefaultTransitionState
    extends State<ChatMessageMenuDefaultTransition>
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
      duration: ChatMessageMenuDefaultTransition.enterDuration,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scale =
        Tween<double>(
          begin: ChatMessageMenuDefaultTransition.enterScale,
          end: 1,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          ),
        );
    unawaited(_controller.forward());
  }

  @override
  void didUpdateWidget(ChatMessageMenuDefaultTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.transition.visible && !_leaving) unawaited(_leave());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    _leaving = true;
    _controller.duration = ChatMessageMenuDefaultTransition.leaveDuration;
    await _controller.reverse();
    if (mounted) widget.transition.onHidden();
  }

  double get _leaveDy {
    if (!_leaving) return 0;
    final t = 1 - _controller.value;
    const slide = ChatMessageMenuDefaultTransition.leaveSlide;
    return t * (widget.transition.origin.y > 0 ? -slide : slide);
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
