import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:flutter/widgets.dart';

/// Reports the painted **message surface** (typically the bubble) so the
/// viewport can resolve **message menu point state** (Inside vs Outside).
///
/// Wrap the bubble chrome — including header, body, and meta — not the full
/// list row. Without this, menu Inside falls back to the text-body bounds and
/// taps on sender/header chrome look like Outside.
///
/// Registers the surface [RenderBox]; hit-tests resolve
/// [RenderBox.localToGlobal] at query time so scrolling without a rebuild
/// does not leave a stale global [Rect].
///
/// The registered surface also feeds the **message menu request**: its live
/// global rect and [shape] become the undimmed hole of the sheet scrim, so
/// the dim frames the bubble rather than the full row.
class ChatMessageSurfaceBounds extends StatefulWidget {
  /// Creates a surface-bounds reporter for [messageId].
  const ChatMessageSurfaceBounds({
    required this.controller,
    required this.messageId,
    required this.child,
    this.shape,
    super.key,
  });

  /// Selection facade that stores the reported box.
  final ChatSelectionController controller;

  /// Message id whose surface is being reported.
  final int messageId;

  /// Outline of the painted surface inside the [child] box, such as the
  /// bubble's [RoundedRectangleBorder] with per-corner radii.
  ///
  /// Only the message menu scrim hole reads it; Inside / Outside hit-testing
  /// uses the box rect. Directional radii resolve against the menu overlay's
  /// [Directionality]. Null leaves the hole at the menu theme's hole radius
  /// around the box. Changing it re-registers on the next frame.
  final ShapeBorder? shape;

  /// Bubble (or other message surface) whose paint box is reported.
  final Widget child;

  @override
  State<ChatMessageSurfaceBounds> createState() =>
      _ChatMessageSurfaceBoundsState();
}

class _ChatMessageSurfaceBoundsState extends State<ChatMessageSurfaceBounds> {
  @override
  void dispose() {
    widget.controller.reportMessageSurfaceBounds(widget.messageId, null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatMessageSurfaceBounds oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        oldWidget.controller != widget.controller) {
      oldWidget.controller.reportMessageSurfaceBounds(
        oldWidget.messageId,
        null,
      );
      _scheduleReport();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _report();
    });
  }

  void _report() {
    switch (context.findRenderObject()) {
      case final RenderBox box when box.hasSize:
        widget.controller.reportMessageSurfaceBounds(
          widget.messageId,
          box,
          shape: widget.shape,
        );
      case _:
        widget.controller.reportMessageSurfaceBounds(widget.messageId, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-register after layout when ancestors rebuild; geometry itself is
    // read live from the [RenderBox] at hit time (scroll-safe).
    _scheduleReport();
    return widget.child;
  }
}
