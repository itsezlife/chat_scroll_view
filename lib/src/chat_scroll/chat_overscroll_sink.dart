import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Which conversation edges hand their unconsumed drag to a
/// [ChatOverscrollSink].
///
/// The oldest edge is the top of the viewport, the newest edge the bottom.
enum ChatOverscrollEdges {
  /// Only the top (oldest) edge hands over. The usual host: a bottom sheet
  /// whose chat feed closes it by pulling down past the oldest message.
  oldest,

  /// Only the bottom (newest) edge hands over.
  newest,

  /// Both edges hand over.
  both;

  /// Whether the oldest (top) edge hands over.
  bool get takesOldest => this != newest;

  /// Whether the newest (bottom) edge hands over.
  bool get takesNewest => this != oldest;
}

/// **Overscroll sink**: the host's receiver for the part of a user drag the
/// viewport cannot scroll, so an ancestor that moves (a draggable sheet, a
/// collapsing header) can take it instead of the [ChatEdgeEffect].
///
/// The viewport alone knows where its conversation edges are, so it alone
/// can say which part of a drag is "past the edge"; a host `Listener` cannot
/// tell a drag that content consumed from one it did not. What the receiver
/// does with the pixels is the host's business: the sink consumes nothing
/// inside the viewport and holds no viewport state.
///
/// Deltas use the chat sign convention: positive moves content down (the
/// finger moves down, revealing older messages and pressing the oldest edge),
/// negative presses the newest edge.
///
/// The hand-over covers the drag path only (touch, stylus, trackpad pan).
/// Mouse wheel, keyboard, scrollbar and programmatic scrolling never reach
/// it, and a content fling that arrives at an edge still uses the viewport's
/// [ChatEdgeEffect] (a momentum scroll reaching the top does not close a
/// sheet).
///
/// While the content rests at a handed-over edge, a drag in either direction
/// is offered to [onDelta] first — the same order a draggable sheet's own
/// scroll position uses: the sheet moves before the list does, in both
/// directions, until the sheet declines. Away from the edge nothing is
/// offered. For short content (everything fits) that is every drag.
///
/// An empty or loading viewport (overlay builders, no scrollable content)
/// forwards every drag the overlay child does not claim to the sink, so the
/// host needs no wrapper.
@immutable
final class ChatOverscrollSink {
  /// A sink fed by [onDelta] and [onEnd].
  const ChatOverscrollSink({
    required this.onDelta,
    required this.onEnd,
    this.onStart,
    this.edges = ChatOverscrollEdges.oldest,
  });

  /// Which edges hand over; default [ChatOverscrollEdges.oldest].
  final ChatOverscrollEdges edges;

  /// A drag started. Optional: stop the receiver's own animation here.
  final VoidCallback? onStart;

  /// Offers [pixels] of the drag, in the chat sign convention, and returns
  /// how many the receiver took.
  ///
  /// The return has the sign of [pixels] and `abs` no larger than it (the
  /// viewport clamps anything else). Return `0` to decline: the viewport then
  /// scrolls its content with the offer (or shows its edge effect for what
  /// cannot scroll). A receiver that is at its own limit — a sheet fully
  /// open, offered an upward drag — returns `0` so the content scrolls.
  final double Function(double pixels) onDelta;

  /// The finger lifted at [velocity] px/s (same sign convention).
  ///
  /// Called once at the end of a drag during which [onDelta] took something.
  /// Return `true` when the receiver takes the release (it settles, snaps or
  /// dismisses with [velocity]): the viewport then starts no content fling.
  /// Return `false` to let the content fling from the release as usual (a
  /// sheet that is fully open and released upward).
  ///
  /// For an overlay viewport the return is ignored.
  final bool Function(double velocity) onEnd;
}

/// Runtime of one [ChatOverscrollSink] on a viewport: decides which part of a
/// drag tick is offered and tracks whether the sink took part of this drag.
///
/// Holds no scroll geometry; the render object passes the pin facts in.
@internal
final class ChatOverscrollHandoff {
  /// The sink currently handed deltas, or `null` for none.
  ChatOverscrollSink? sink;

  bool _engaged = false;

  /// Whether the sink took any pixels since [beginDrag].
  bool get engaged => _engaged;

  /// A drag starts: forget the previous one and tell the sink.
  void beginDrag() {
    _engaged = false;
    sink?.onStart?.call();
  }

  /// Offers one drag tick to the sink and returns the pixels it took.
  ///
  /// [delta] is the whole tick; [unconsumed] the part content could not
  /// consume. At a pinned handed edge the whole tick is offered (both
  /// directions); otherwise only a handed edge's [unconsumed] part.
  double offer({
    required double delta,
    required double unconsumed,
    required bool oldestPinned,
    required bool newestPinned,
  }) {
    final target = sink;
    if (target == null || delta == 0) return 0;
    final edges = target.edges;
    final pinned =
        (edges.takesOldest && oldestPinned) ||
        (edges.takesNewest && newestPinned);
    final offered = pinned
        ? delta
        : ((unconsumed > 0 && edges.takesOldest) ||
                  (unconsumed < 0 && edges.takesNewest)
              ? unconsumed
              : 0.0);
    if (offered == 0) return 0;
    final raw = target.onDelta(offered);
    final taken = (offered > 0 ? raw.clamp(0, offered) : raw.clamp(offered, 0))
        .toDouble();
    if (taken != 0) _engaged = true;
    return taken;
  }

  /// The drag ended at [velocity]; returns whether the sink took the release.
  bool endDrag(double velocity) {
    final target = sink;
    if (target == null || !_engaged) return false;
    _engaged = false;
    return target.onEnd(velocity);
  }

  VerticalDragGestureRecognizer? _overlayDrag;

  /// Overlay mode (empty, loading): routes a fresh press to a drag
  /// recognizer that forwards raw deltas to the sink. No-op without a sink.
  void addOverlayPointer(PointerDownEvent event) {
    final target = sink;
    if (target == null) return;
    final drag = _overlayDrag ??=
        VerticalDragGestureRecognizer(
            debugOwner: this,
            supportedDevices: const <PointerDeviceKind>{
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.trackpad,
            },
          )
          ..onStart = ((_) => sink?.onStart?.call())
          ..onUpdate = ((details) => sink?.onDelta(details.delta.dy))
          ..onEnd = ((details) => sink?.onEnd(details.primaryVelocity ?? 0));
    if (event.kind != PointerDeviceKind.mouse) drag.addPointer(event);
  }

  /// Drops the overlay recognizer (sink change, overlay exit, dispose).
  void disposeOverlayDrag() {
    _overlayDrag?.dispose();
    _overlayDrag = null;
  }
}
