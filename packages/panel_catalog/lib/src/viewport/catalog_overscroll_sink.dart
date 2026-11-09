import 'package:flutter/foundation.dart';

/// **Overscroll sink**: the host's receiver for the part of a user drag the
/// catalogue cannot scroll past its top edge, so an ancestor that moves (a
/// sheet the grid sits in) can take it instead of the drag going nowhere.
///
/// Only the viewport knows whether its content is at the top and how much of
/// a drag it consumed, so only it can say which part of a drag is past the
/// edge; a host `Listener` cannot tell the two apart. What the receiver does
/// with the pixels is its own business: the sink holds no viewport state.
///
/// Pixels and velocities are in the finger's sign: positive is a finger
/// moving down, which pulls past the top edge; negative is a finger moving
/// up, toward the content below.
///
/// The hand-over covers the drag path only (touch, stylus, trackpad pan). The
/// mouse wheel, keyboard focus moves, a fling and programmatic scrolling never
/// reach it: a fling that arrives at the top stops there.
///
/// While the content rests at the top (always, for content that fits), every
/// drag tick is offered to [onDelta] first, in both directions: the receiver
/// moves before the content does, until it declines. Away from the top only
/// the part of a downward tick that content cannot scroll is offered.
@immutable
final class CatalogOverscrollSink {
  /// A sink fed by [onDelta] and [onEnd].
  const CatalogOverscrollSink({
    required this.onDelta,
    required this.onEnd,
    this.onStart,
    this.restBeforePull = Duration.zero,
  });

  /// A drag started. Optional: stop the receiver's own animation here.
  final VoidCallback? onStart;

  /// Offers [pixels] of the drag and returns how many the receiver took.
  ///
  /// The return has the sign of [pixels] and is no larger (the viewport
  /// clamps anything else). Return `0` to decline: the content then scrolls
  /// with the offer. A receiver that holds nothing, offered a finger moving
  /// up, returns `0` so the content scrolls.
  final double Function(double pixels) onDelta;

  /// The finger lifted at [velocity] logical px/s (finger sign).
  ///
  /// Called once at the end of a drag during which [onDelta] took something,
  /// or with `0` when such a drag is cancelled. Return `true` when the
  /// receiver takes the release (it settles, springs back or dismisses): the
  /// viewport then starts no content fling. Return `false` to let the content
  /// fling as usual (the receiver gave back all it took and the finger went
  /// on to scroll the content).
  final bool Function(double velocity) onEnd;

  /// How long, within one drag, the content must have rested at the top
  /// before a pull past it is offered.
  ///
  /// A drag that scrolls the content back to the top quickly carries on
  /// past it; without a rest that tail would move the receiver (and close a
  /// sheet) though the user only meant to scroll. Pulls inside the window
  /// are dropped; a finger that keeps pulling at the top past it reaches the
  /// receiver. Measured on the drag's own event times; a drag that started
  /// with the content at the top is never held back. Zero offers at once.
  final Duration restBeforePull;
}

/// Runtime of one [CatalogOverscrollSink] on a viewport: decides which part
/// of a drag tick is offered and tracks whether the sink took part of this
/// drag.
///
/// Holds no scroll geometry; the render object passes the facts in.
@internal
final class CatalogOverscrollHandoff {
  /// The sink currently handed deltas, or `null` for none.
  CatalogOverscrollSink? sink;

  bool _engaged = false;

  /// When content last moved in this drag, or null when it has not.
  Duration? _contentMovedAt;

  /// Whether the sink took any pixels since [beginDrag].
  bool get engaged => _engaged;

  /// A drag starts: forget the previous one and tell the sink.
  void beginDrag() {
    _engaged = false;
    _contentMovedAt = null;
    sink?.onStart?.call();
  }

  /// Offers one drag tick of [delta] (finger sign) to the sink and returns
  /// the pixels it took.
  ///
  /// [pinned] is whether the content is at the top before the tick; [room]
  /// how far the content can still scroll toward the top. [time] is the
  /// tick's event time, or null when the platform gave none.
  double offer({
    required double delta,
    required bool pinned,
    required double room,
    required Duration? time,
  }) {
    final target = sink;
    if (target == null || delta == 0) return 0;
    final offered = pinned ? delta : (delta > room ? delta - room : 0.0);
    if (offered == 0) return 0;
    if (offered > 0 && !_rested(target, time)) return 0;
    final raw = target.onDelta(offered);
    final taken = (offered > 0 ? raw.clamp(0, offered) : raw.clamp(offered, 0))
        .toDouble();
    if (taken != 0) _engaged = true;
    return taken;
  }

  /// Content moved during this drag at [time] (null when unknown).
  void contentMoved(Duration? time) {
    _contentMovedAt = time ?? Duration.zero;
  }

  /// Whether a pull may reach [target] at [time]: the drag never moved the
  /// content, or it has rested at the top long enough.
  bool _rested(CatalogOverscrollSink target, Duration? time) {
    final moved = _contentMovedAt;
    if (moved == null || target.restBeforePull == Duration.zero) return true;
    // A platform without event times cannot measure the rest: hold back.
    if (time == null) return false;
    return time - moved >= target.restBeforePull;
  }

  /// The drag ended at [velocity]; returns whether the sink took the release.
  bool endDrag(double velocity) {
    final target = sink;
    final engaged = _engaged;
    _engaged = false;
    _contentMovedAt = null;
    if (target == null || !engaged) return false;
    return target.onEnd(velocity);
  }
}
