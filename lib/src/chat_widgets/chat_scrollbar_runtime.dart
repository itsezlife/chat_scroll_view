import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Where the press that started a grab landed.
@internal
enum ChatScrollbarPress {
  /// On the thumb: the grab keeps the pointer's offset into the thumb, and
  /// nothing moves until the pointer does.
  thumb,

  /// On the track beside the thumb: the thumb centres on the pointer at
  /// once and the grab continues from there.
  track,
}

/// Where a grab puts the thumb: [progress] in `[0, 1]` along the track, and
/// [spanShare], the visible band's share of the known span frozen when the
/// grab started. The render object inverts its thumb-progress mapping with
/// both to find the band position under the pointer.
typedef ChatScrollbarGrabPosition = ({double progress, double spanShare});

/// Per-viewport scrollbar state: the frame resolved at the last paint and
/// the thumb's motion — at rest, grabbed by a pointer, or settling after a
/// grab.
///
/// Knows nothing of the data source, the controller, or anchor math — the
/// render object computes the band's thumb progress and span share and
/// hands them to [resolve], and maps a [ChatScrollbarGrabPosition] back to
/// a band position. Paint and grab hit-testing both read [frame], so a
/// press lands on exactly what was last painted; between a layout and its
/// paint no pointer event is dispatched, so [frame] is never staler than
/// the pixels on screen.
///
/// ## Motion
///
/// - **Rest** — the thumb shows the band: position and length from
///   [resolve]'s progress and span share.
/// - **Grab** — the thumb follows the pointer, keeping the offset at which
///   the press met it. Its length and the span share are frozen at the
///   press, so the travel the pointer moves through, and so the
///   pointer-to-band mapping, stay fixed for the whole grab.
/// - **Settle** — after [endGrab], the thumb eases from where the pointer
///   left it to the band's thumb over [settleDuration], advanced by
///   [tickSettle]. The band keeps moving the target while it settles.
///
/// The settle is not an `AnimationController`: the owner is a render object
/// with no `TickerProvider`; the render object's own ticker drives it.
@internal
final class ChatScrollbarRuntime {
  /// Width of the grab strip along the viewport's trailing edge.
  static const double stripWidth = 20;

  /// How long the thumb takes to ease from the pointer back to the band's
  /// position after a grab ends.
  static const Duration settleDuration = Duration(milliseconds: 250);

  /// Curve applied to the settle's linear time fraction; the thumb's top
  /// and length are lerped by its output.
  static const Curve settleCurve = Curves.easeOut;

  ChatScrollbarFrame? _frame;
  double _viewportWidth = 0;
  double _spanShare = 0;
  _ThumbMotion? _motion;

  /// The frame resolved at the last paint, or `null` when no scrollbar was
  /// painted: no preset painter, nothing to scroll, or overlay mode.
  ChatScrollbarFrame? get frame => _frame;

  /// Whether a pointer currently holds a grab.
  bool get isGrabbing => switch (_motion) {
    _Grab() => true,
    _ => false,
  };

  /// Whether the thumb is easing back to the band after a grab; the render
  /// object keeps its ticker alive and calls [tickSettle] until it is not.
  bool get isSettling => switch (_motion) {
    _Settle() => true,
    _ => false,
  };

  /// Resolves this paint's frame for [painter] and stores it as [frame].
  ///
  /// [progress] in `[0, 1]` places the band's thumb along the track;
  /// [thumbFraction] is the visible band's share of the known span. At rest
  /// the thumb shows exactly that. While grabbed it shows the pointer's
  /// position with the frozen length; while settling, a blend of the two.
  /// Returns `null` (and clears [frame]) when the track has no length or
  /// the thumb, floored at the painter's minimum, would leave nothing to
  /// travel.
  ChatScrollbarFrame? resolve({
    required ChatScrollbarPainter painter,
    required Size size,
    required double topInset,
    required double bottomInset,
    required TextDirection textDirection,
    required double progress,
    required double thumbFraction,
  }) {
    final margin = painter.mainAxisMargin;
    final trackTop = topInset + margin;
    final trackBottom = size.height - bottomInset - margin;
    final trackLength = trackBottom - trackTop;
    final bandLength = math.min(
      math.max(trackLength * thumbFraction, painter.minThumbLength),
      trackLength,
    );
    _spanShare = thumbFraction;
    final bandOffset = (trackLength - bandLength) * progress.clamp(0.0, 1.0);
    final (thumbLength, thumbOffset) = switch (_motion) {
      null => (bandLength, bandOffset),
      final _Grab grab => (
        grab.lengthOn(trackLength),
        grab.offsetOn(trackTop, trackLength),
      ),
      final _Settle settle => (
        lerpDouble(settle.fromLength, bandLength, settle.eased)!,
        lerpDouble(settle.fromOffset, bandOffset, settle.eased)!,
      ),
    };
    if (trackLength <= 0 || trackLength - thumbLength <= 0) {
      clear();
      return null;
    }

    final thickness = painter.trackThickness;
    final (left, right) = switch (textDirection) {
      TextDirection.ltr => (
        size.width - painter.crossAxisMargin - thickness,
        size.width - painter.crossAxisMargin,
      ),
      TextDirection.rtl => (
        painter.crossAxisMargin,
        painter.crossAxisMargin + thickness,
      ),
    };
    final thumbTop =
        trackTop + thumbOffset.clamp(0.0, trackLength - thumbLength);
    _viewportWidth = size.width;
    return _frame = ChatScrollbarFrame(
      trackRect: Rect.fromLTRB(left, trackTop, right, trackBottom),
      thumbRect: Rect.fromLTRB(left, thumbTop, right, thumbTop + thumbLength),
      textDirection: textDirection,
      grabFactor: isGrabbing ? 1.0 : 0.0,
    );
  }

  /// Drops [frame] and any settle — with no scrollbar painted there is
  /// nothing to ease. A grab survives: its pointer stays owned until it
  /// lifts.
  void clear() {
    _frame = null;
    if (isSettling) _motion = null;
  }

  /// Drops [frame] and all motion, a grab included. For a render object
  /// leaving the tree, where the grabbing pointer's remaining events never
  /// arrive.
  void reset() {
    _frame = null;
    _motion = null;
  }

  /// Starts a grab when [event] lands in the strip: [stripWidth] wide on the
  /// trailing edge of [frame]'s direction, over the track's vertical span,
  /// both bounds inclusive. Replaces a settle in flight.
  ///
  /// Returns where the press landed, or `null` when it missed the strip and
  /// no grab started. On [ChatScrollbarPress.track] the thumb is centred on
  /// the pointer; read [grabPosition] for the band position that asks for.
  ChatScrollbarPress? tryStartGrab(PointerDownEvent event) {
    final frame = _frame;
    if (frame == null) return null;
    final Offset(:dx, :dy) = event.localPosition;
    final inStrip = switch (frame.textDirection) {
      TextDirection.ltr => dx >= _viewportWidth - stripWidth,
      TextDirection.rtl => dx <= stripWidth,
    };
    if (!inStrip || dy < frame.trackRect.top || dy > frame.trackRect.bottom) {
      return null;
    }
    final thumb = frame.thumbRect;
    final onThumb = dy >= thumb.top && dy <= thumb.bottom;
    _motion = _Grab(
      pointer: event.pointer,
      pointerY: dy,
      grabOffset: onThumb ? dy - thumb.top : thumb.height / 2,
      thumbLength: thumb.height,
      spanShare: _spanShare,
    );
    return onThumb ? ChatScrollbarPress.thumb : ChatScrollbarPress.track;
  }

  /// The grab's thumb position against the last resolved track, or `null`
  /// when no grab is held or no frame is resolved.
  ChatScrollbarGrabPosition? get grabPosition => switch ((_motion, _frame)) {
    (final _Grab grab, final frame?) => (
      progress: grab.progressOn(frame.trackRect.top, frame.trackRect.height),
      spanShare: grab.spanShare,
    ),
    _ => null,
  };

  /// Moves the grab to the pointer at [localY] and returns the new
  /// [grabPosition]. The next [resolve] paints the thumb there.
  ChatScrollbarGrabPosition? moveGrab(double localY) {
    if (_motion case final _Grab grab) grab.pointerY = localY;
    return grabPosition;
  }

  /// Whether [event] belongs to the pointer holding the grab.
  bool ownsPointer(PointerEvent event) => switch (_motion) {
    _Grab(:final pointer) => pointer == event.pointer,
    _ => false,
  };

  /// Ends the grab, if any, and starts the settle from the thumb the grab
  /// last asked for. Without a resolved frame the thumb goes straight to
  /// rest.
  void endGrab() {
    if (_motion case final _Grab grab) {
      _motion = switch (_frame) {
        ChatScrollbarFrame(:final trackRect) => _Settle(
          fromOffset: grab.offsetOn(trackRect.top, trackRect.height),
          fromLength: grab.lengthOn(trackRect.height),
        ),
        null => null,
      };
    }
  }

  /// Advances the settle to the ticker time [elapsed] and returns whether
  /// the thumb moved and needs a repaint. The first tick after [endGrab]
  /// starts the clock, so the first settle frame still shows the pointer's
  /// position; the tick past [settleDuration] returns the thumb to rest.
  bool tickSettle(Duration elapsed) {
    if (_motion case final _Settle settle) {
      final start = settle.start ??= elapsed;
      final t =
          (elapsed - start).inMicroseconds / settleDuration.inMicroseconds;
      if (t >= 1) {
        _motion = null;
      } else {
        settle.eased = settleCurve.transform(t);
      }
      return true;
    }
    return false;
  }
}

/// The thumb's motion away from rest; `null` in [ChatScrollbarRuntime] is
/// rest.
sealed class _ThumbMotion {}

/// A pointer holding the thumb.
final class _Grab extends _ThumbMotion {
  _Grab({
    required this.pointer,
    required this.pointerY,
    required this.grabOffset,
    required this.thumbLength,
    required this.spanShare,
  });

  final int pointer;

  /// The pointer's latest viewport-local Y.
  double pointerY;

  /// Distance from the thumb's top to the pointer, kept for the whole grab.
  final double grabOffset;

  /// Thumb length at the press.
  final double thumbLength;

  /// The visible band's share of the known span at the press.
  final double spanShare;

  /// [thumbLength] fitted into a track of [trackLength].
  double lengthOn(double trackLength) => math.min(thumbLength, trackLength);

  /// Distance from the track's top at [trackTop] to the thumb's top, which
  /// sits [grabOffset] above the pointer, clamped to the thumb's travel.
  double offsetOn(double trackTop, double trackLength) =>
      (pointerY - grabOffset - trackTop).clamp(
        0.0,
        math.max<double>(0, trackLength - lengthOn(trackLength)),
      );

  /// [offsetOn] as a share of the thumb's travel, in `[0, 1]`; `0` when the
  /// thumb leaves no travel.
  double progressOn(double trackTop, double trackLength) {
    final travel = trackLength - lengthOn(trackLength);
    if (travel <= 0) return 0;
    return offsetOn(trackTop, trackLength) / travel;
  }
}

/// The thumb easing from where a grab left it back to the band: its top's
/// distance from the track top and its length both run from the grab's
/// values to the band's, so the painted rect moves in one piece.
final class _Settle extends _ThumbMotion {
  _Settle({required this.fromOffset, required this.fromLength});

  final double fromOffset;
  final double fromLength;

  /// Ticker time of the first tick after release.
  Duration? start;

  /// [ChatScrollbarRuntime.settleCurve] at the settle's current time, from
  /// `0` (the grab's thumb) to `1` (the band's).
  double eased = 0;
}
