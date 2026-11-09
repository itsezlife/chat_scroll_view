import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

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
/// the part of a downward tick that content cannot scroll is offered, on the
/// same tick that brings the content to the top.
@immutable
final class CatalogOverscrollSink {
  /// A sink fed by [onDelta] and [onEnd].
  const CatalogOverscrollSink({
    required this.onDelta,
    required this.onEnd,
    this.onStart,
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

  /// The finger lifted; [velocity] is that of the receiver's own share of
  /// the drag, in logical px/s (finger sign).
  ///
  /// It is measured on the pixels the receiver took, not on the finger: a
  /// fast scroll that reaches the top and runs a little past it, the finger
  /// slowing, is a slow pull, though the finger's release velocity is still
  /// the scroll's. A share too short to measure reports `0`.
  ///
  /// Called once at the end of a drag during which [onDelta] took something,
  /// or with `0` when such a drag is cancelled. Return `true` when the
  /// receiver takes the release (it settles, springs back or dismisses): the
  /// viewport then starts no content fling. Return `false` to let the content
  /// fling as usual (the receiver gave back all it took and the finger went
  /// on to scroll the content).
  final bool Function(double velocity) onEnd;
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

  /// What the sink took in this drag, summed, against the ticks' event times:
  /// the velocity [endDrag] reports.
  VelocityTracker? _share;
  double _taken = 0;

  /// Whether the sink took any pixels since [beginDrag].
  bool get engaged => _engaged;

  /// A drag starts: forget the previous one and tell the sink.
  void beginDrag() {
    _reset();
    sink?.onStart?.call();
  }

  void _reset() {
    _engaged = false;
    _share = null;
    _taken = 0;
  }

  /// Offers one drag tick of [delta] (finger sign) to the sink and returns
  /// the pixels it took.
  ///
  /// [pinned] is whether the content is at the top before the tick; [room]
  /// how far the content can still scroll toward the top. [time] is the
  /// tick's event time, or null when the platform gave none (the share's
  /// velocity is then not measured).
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
    final raw = target.onDelta(offered);
    final taken = (offered > 0 ? raw.clamp(0, offered) : raw.clamp(offered, 0))
        .toDouble();
    if (taken == 0) return 0;
    _engaged = true;
    _taken += taken;
    if (time != null) {
      (_share ??= VelocityTracker.withKind(
        PointerDeviceKind.touch,
      )).addPosition(time, Offset(0, _taken));
    }
    return taken;
  }

  /// The drag ended; returns whether the sink took the release, which it is
  /// handed at the velocity of its own share (`0` for a [cancelled] drag).
  bool endDrag({bool cancelled = false}) {
    final target = sink;
    final engaged = _engaged;
    final velocity = cancelled
        ? 0.0
        : _share?.getVelocityEstimate()?.pixelsPerSecond.dy ?? 0.0;
    _reset();
    if (target == null || !engaged) return false;
    return target.onEnd(velocity);
  }
}
