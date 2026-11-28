import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

/// The error badge beside the time of a failed message.
///
/// A tap on it (a click on desktop) opens the message's menu, Retry and
/// Delete: the badge registers with the selection facade as a part of the
/// message's body with the `menu` role, so the viewport arbitrates the tap
/// as for any part and opens the menu through the host's own menu entry,
/// with a [DemoErrorBadgePart] on the request. It takes no tap of its own,
/// so in message selection a tap on it toggles the row as anywhere else on
/// the message.
///
/// To assistive technology it carries a retry hint and a custom action
/// that calls [onRetry]; the status itself, "not sent", is the time's.
class DemoErrorBadge extends StatefulWidget {
  /// The badge of the message [messageId], registered with [selection].
  const DemoErrorBadge({
    required this.messageId,
    required this.selection,
    required this.onRetry,
    super.key,
  });

  /// The failed message.
  final int messageId;

  /// The facade the badge registers its part with.
  final ChatSelectionController selection;

  /// Sends the message again: the retry semantics action.
  final VoidCallback onRetry;

  /// The drawn circle's diameter.
  static const double size = 16;

  /// The square a press finds the badge in, around the circle: the circle
  /// alone is smaller than a finger.
  static const double hitSize = 24;

  /// The badge's fill.
  static const Color color = Color(0xFFE53935);

  @override
  State<DemoErrorBadge> createState() => _DemoErrorBadgeState();
}

class _DemoErrorBadgeState extends State<DemoErrorBadge>
    implements ChatNonTextBody {
  final GlobalKey _hitBox = GlobalKey();
  Object? _token;
  ChatSelectionController? _registeredWith;
  int? _registeredId;

  // The kind of the press under way, recorded before the viewport asks for
  // the part: this leaf's listener sees the down before its ancestors do.
  PointerDeviceKind _pointerKind = PointerDeviceKind.touch;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant DemoErrorBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection) ||
        oldWidget.messageId != widget.messageId) {
      _unregister();
      _register();
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  void _register() {
    _registeredWith = widget.selection;
    _registeredId = widget.messageId;
    _token = widget.selection.putNonTextBody(widget.messageId, this);
  }

  void _unregister() {
    if ((_registeredWith, _registeredId) case (final selection?, final id?)) {
      selection.removeNonTextBody(id, token: _token);
    }
    _registeredWith = null;
    _registeredId = null;
    _token = null;
  }

  // --- ChatNonTextBody ------------------------------------------------------

  Rect? get _hitRect => switch (_hitBox.currentContext?.findRenderObject()) {
    final RenderBox box when box.attached && box.hasSize =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  @override
  Rect? get globalBounds => _hitRect;

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) {
    final rect = _hitRect;
    if (rect == null || !mounted || !rect.contains(globalOffset)) return null;
    return ChatInlineHit.bodyPart(
      messageId: widget.messageId,
      partId: DemoErrorBadgePart(widget.messageId, pointerKind: _pointerKind),
      role: ChatBodyPartRole.menu,
      rect: rect,
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    hint: DemoOutgoingStrings.retryHint,
    customSemanticsActions: {
      const CustomSemanticsAction(label: DemoOutgoingStrings.retry):
          widget.onRetry,
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _pointerKind = event.kind,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox.square(
          key: _hitBox,
          dimension: DemoErrorBadge.hitSize,
          child: const Center(
            child: SizedBox.square(
              dimension: DemoErrorBadge.size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DemoErrorBadge.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.priority_high_rounded,
                  size: 12,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
