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
class ChatMessageSurfaceBounds extends StatefulWidget {
  /// Creates a surface-bounds reporter for [messageId].
  const ChatMessageSurfaceBounds({
    required this.controller,
    required this.messageId,
    required this.child,
    super.key,
  });

  /// Selection facade that stores the reported box.
  final ChatSelectionController controller;

  /// Message id whose surface is being reported.
  final int messageId;

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
        widget.controller.reportMessageSurfaceBounds(widget.messageId, box);
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
