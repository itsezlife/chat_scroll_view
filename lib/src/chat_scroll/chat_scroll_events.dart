import 'package:chat_scroll_view/src/chat_scroll/animate_to_path.dart';

/// Sealed hierarchy of scroll-side events emitted by the chat viewport.
///
/// Subscribe via [ChatScrollController.addScrollListener] to react to user
/// drags / flings / programmatic jumps without conflating them — e.g. dismiss
/// the keyboard on a user drag but not on a `jumpTo`, debounce read-receipts
/// while a fling is in flight, or show a "↓ new messages" pill when the user
/// has scrolled away from the newest.
sealed class ChatScrollEvent {
  const ChatScrollEvent();
}

/// User touched the viewport and started dragging.
class ChatUserDragStart extends ChatScrollEvent {
  /// Emitted when the user begins dragging the viewport.
  const ChatUserDragStart();
}

/// User lifted the finger; [velocity] is the terminal pixel/second velocity
/// (signed: positive = revealing older, negative = revealing newer).
class ChatUserDragEnd extends ChatScrollEvent {
  /// Emitted when the user lifts their finger after a drag.
  const ChatUserDragEnd(this.velocity);

  /// Terminal drag velocity in pixels/second; signed like scroll deltas
  /// (positive reveals older messages).
  final double velocity;
}

/// A fling simulation just started after a drag end. [velocity] is the
/// initial velocity in pixel/second.
class ChatFlingStart extends ChatScrollEvent {
  /// Emitted when inertial scrolling begins after a drag release.
  const ChatFlingStart(this.velocity);

  /// Initial fling velocity in pixels/second passed to the physics simulation.
  final double velocity;
}

/// The fling simulation just terminated (either naturally or cancelled).
class ChatFlingEnd extends ChatScrollEvent {
  /// Emitted when the fling simulation finishes or is cancelled.
  const ChatFlingEnd();
}

/// `controller.jumpTo` was called programmatically.
class ChatProgrammaticJump extends ChatScrollEvent {
  /// Emitted when [ChatScrollController.jumpTo] repositions the anchor.
  const ChatProgrammaticJump(this.targetId);

  /// Message id the jump targeted.
  final int targetId;
}

/// `controller.animateTo` started; carries the target id and the duration.
class ChatAnimateStart extends ChatScrollEvent {
  /// Emitted when [ChatScrollController.animateTo] begins scrolling.
  const ChatAnimateStart(this.targetId, this.duration);

  /// Message id the animation is scrolling toward.
  final int targetId;

  /// Requested animation length — the viewport may clamp it when the target
  /// is already on screen.
  final Duration duration;
}

/// `controller.animateTo`'s animation finished.
///
/// Emitted once per flight that emitted [ChatAnimateStart] — when it
/// settles and when it is cancelled — before the `animateTo` future
/// completes. A call coalesced onto an in-flight animate, an ignored call,
/// and an `animateTo` with no viewport bound (placed through
/// [ChatScrollController.jumpTo], reported as [ChatProgrammaticJump]) emit
/// none.
class ChatAnimateEnd extends ChatScrollEvent {
  /// Emitted when an [ChatScrollController.animateTo] flight settles or is
  /// cancelled.
  const ChatAnimateEnd(this.targetId, {this.path = AnimateToPath.none});

  /// Message id that was scrolled to.
  final int targetId;

  /// Path the flight took to [targetId] — see [AnimateToPath] for when each
  /// value is reported, including cancelled flights.
  final AnimateToPath path;
}

/// `controller.scrollBy` was called programmatically. [delta] is the pixel
/// shift applied to the anchor; positive = revealing older messages.
class ChatProgrammaticScroll extends ChatScrollEvent {
  /// Emitted when [ChatScrollController.scrollBy] shifts the anchor.
  const ChatProgrammaticScroll(this.delta);

  /// Pixel delta applied to the anchor; positive reveals older messages.
  final double delta;
}

/// Per-frame user-driven scroll (drag, wheel, or fling tick).
///
/// [delta] uses the same sign as [ChatProgrammaticScroll] / drag
/// (`positive` reveals older messages). Not emitted for follow-tail pin,
/// bounceback, close-path [ChatScrollController.animateTo], or span
/// auto-scroll — those are not user pan gestures.
class ChatViewportScrolled extends ChatScrollEvent {
  /// Emitted when the viewport applies a user-driven pixel delta this frame.
  const ChatViewportScrolled(this.delta);

  /// Pixel delta applied this frame; positive reveals older messages.
  final double delta;
}
