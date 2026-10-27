import 'package:chat_scroll_view/src/chat_widgets/chat_selection_gesture_exclusion.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Marks a region of a message row as **not part of the message tap**, for a
/// mouse or trackpad.
///
/// The viewport's selection pointer listens above the gesture arena, so a
/// detector inside the row cannot keep a press from reaching it. A primary
/// press that goes down on a barrier is not a message press: it does not toggle
/// or start **message selection**, start a drag-select span, arm **text
/// selection**, fire [ChatScrollView.onIdleMessageTap] or activate an inline
/// hit under it (a time pill over a sticker's corner is not the sticker).
///
/// What a barrier leaves alone:
///
/// - A **secondary** click still reaches
///   [ChatScrollView.onSecondaryMessageTap]: the message menu opens as it does
///   beside the region.
/// - A tap still dismisses a live **text selection**.
/// - Hover, cursor and everything the child itself handles.
///
/// Touch and stylus are never blocked: a tap on the status of a row on a phone
/// is a message tap, and in **message selection** it toggles the row.
///
/// Use it around status chrome that is not the message body: a hover-revealed
/// time pill, delivery ticks. A host that wants the press to do something of
/// its own puts a detector inside [child]; it wins the arena as usual, and the
/// message still does not see the press.
///
/// The region is the hit-test area of [child], so a child that does not size to
/// the chrome, or that cannot be hit, bars nothing.
class ChatMessageTapBarrier extends StatelessWidget {
  /// Bars the message tap for mouse presses on [child].
  const ChatMessageTapBarrier({
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// The chrome the barrier covers.
  final Widget child;

  /// When false the region is an ordinary part of the message.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // Hit-test dispatch reaches this leaf listener before the viewport
    // ancestor, so the bar is visible when the viewport's pointer layer takes
    // the same down (see ChatSelectionGestureExclusion).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _bar,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: child,
    );
  }

  static bool _isMouseLike(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse ||
      event.kind == PointerDeviceKind.trackpad;

  static void _bar(PointerDownEvent event) {
    if (_isMouseLike(event)) ChatSelectionGestureExclusion.bar(event.pointer);
  }

  // The viewport takes the bar on the same down; this clears one it never
  // took (no viewport above, or a selection-less one), so it cannot leak into a
  // later press that reuses the pointer id.
  static void _release(PointerEvent event) =>
      ChatSelectionGestureExclusion.takeBarred(event.pointer);
}
