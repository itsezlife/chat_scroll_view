import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Per-viewport scrollbar state: the frame resolved at the last paint and
/// the pointer that holds a grab.
///
/// Knows nothing of the data source, the controller, or anchor math — the
/// render object computes thumb progress and length share from the anchor
/// and hands them to [resolve]. Paint and grab hit-testing both read
/// [frame], so a press lands on exactly what was last painted; between a
/// layout and its paint no pointer event is dispatched, so [frame] is never
/// staler than the pixels on screen.
@internal
final class ChatScrollbarRuntime {
  /// Width of the grab strip along the viewport's trailing edge.
  static const double stripWidth = 20;

  ChatScrollbarFrame? _frame;
  double _viewportWidth = 0;
  int? _pointer;

  /// The frame resolved at the last paint, or `null` when no scrollbar was
  /// painted: no preset painter, nothing to scroll, or overlay mode.
  ChatScrollbarFrame? get frame => _frame;

  /// Whether a pointer currently holds a grab.
  bool get isGrabbing => _pointer != null;

  /// Resolves this paint's frame for [painter] and stores it as [frame].
  ///
  /// [progress] in `[0, 1]` places the thumb along the track; [thumbFraction]
  /// is the visible band's share of the known span. Returns `null` (and
  /// clears [frame]) when the track has no length or the thumb, floored at
  /// the painter's minimum, would leave nothing to travel.
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
    final thumbLength = math.min(
      math.max(trackLength * thumbFraction, painter.minThumbLength),
      trackLength,
    );
    if (trackLength <= 0 || trackLength - thumbLength <= 0) {
      clear();
      return null;
    }
    final travel = trackLength - thumbLength;

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
    final thumbTop = trackTop + travel * progress.clamp(0.0, 1.0);
    _viewportWidth = size.width;
    return _frame = ChatScrollbarFrame(
      trackRect: Rect.fromLTRB(left, trackTop, right, trackBottom),
      thumbRect: Rect.fromLTRB(left, thumbTop, right, thumbTop + thumbLength),
      textDirection: textDirection,
      grabFactor: isGrabbing ? 1.0 : 0.0,
    );
  }

  /// Drops [frame].
  void clear() => _frame = null;

  /// Starts a grab when [event] lands in the strip: [stripWidth] wide on the
  /// trailing edge of [frame]'s direction, over the track's vertical span,
  /// both bounds inclusive. Returns whether the grab started.
  bool tryStartGrab(PointerDownEvent event) {
    final frame = _frame;
    if (frame == null) return false;
    final Offset(:dx, :dy) = event.localPosition;
    final inStrip = switch (frame.textDirection) {
      TextDirection.ltr => dx >= _viewportWidth - stripWidth,
      TextDirection.rtl => dx <= stripWidth,
    };
    if (!inStrip || dy < frame.trackRect.top || dy > frame.trackRect.bottom) {
      return false;
    }
    _pointer = event.pointer;
    return true;
  }

  /// Whether [event] belongs to the pointer holding the grab.
  bool ownsPointer(PointerEvent event) => event.pointer == _pointer;

  /// Ends the grab, if any.
  void endGrab() => _pointer = null;

  /// Thumb progress that centres the thumb on [localY], clamped to
  /// `[0, 1]`, or `null` when no frame is resolved.
  double? progressAt(double localY) {
    final frame = _frame;
    if (frame == null) return null;
    final track = frame.trackRect;
    final thumbLength = frame.thumbRect.height;
    final travel = track.height - thumbLength;
    return ((localY - track.top - thumbLength / 2) / travel).clamp(0.0, 1.0);
  }
}
