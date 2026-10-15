import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/scheduler.dart';

/// Tells a [GlyphAtlas] when the catalog is moving and, once it stops, which
/// glyphs are on screen, so the bake never competes with motion and bakes the
/// visible band first.
///
/// The viewport is the only one who knows. This class turns what it sees into
/// the two facts the atlas wants:
///
/// - **moving**: the paint offset changed this frame, a drag is in progress, or
///   the viewport says it is animating (fling, section jump). Reported as
///   `true` at once, so the bake pauses before its next step, and as `false`
///   only after a whole frame passed with nothing moving;
/// - **settled**: at that moment, [GlyphAtlas.prioritise] gets the glyphs now
///   on screen.
///
/// Offset change is read at paint, which covers every way of moving (wheel,
/// jump, animation) without listening to each. A rest between two ticks of an
/// animation is not mistaken for settling: [isAnimating] is asked first.
/// A finger that holds still after dragging is not a frame without motion, so
/// the drag flag keeps the bake paused until the finger lifts.
///
/// Nothing here holds a timer. The only pending work is one post-frame callback
/// while the catalog moves, and none when it rests.
final class CatalogBakeActivity {
  /// Creates the reporter for [atlas].
  ///
  /// [isAnimating] says whether the viewport is mid-fling or mid-jump;
  /// [visibleGlyphs] lists the unicode glyphs on screen, top first.
  CatalogBakeActivity({
    required GlyphAtlas atlas,
    required bool Function() isAnimating,
    required Iterable<String> Function() visibleGlyphs,
    SchedulerBinding? binding,
  }) : _atlas = atlas,
       _isAnimating = isAnimating,
       _visibleGlyphs = visibleGlyphs,
       _binding = binding ?? SchedulerBinding.instance;

  final GlyphAtlas _atlas;
  final bool Function() _isAnimating;
  final Iterable<String> Function() _visibleGlyphs;
  final SchedulerBinding _binding;

  double? _lastOffset;
  bool _movedThisFrame = false;
  bool _dragging = false;
  bool _reportedMoving = false;
  bool _checkScheduled = false;
  bool _prioritiseOnNextPaint = true;
  bool _disposed = false;

  /// A drag began (`true`) or ended or was cancelled (`false`).
  set dragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    _noteActivity();
  }

  /// The slots changed, so what is on screen may have too: say so at the next
  /// paint that is not a scroll.
  void visibleBandChanged() => _prioritiseOnNextPaint = true;

  /// Called from every paint with the scroll offset it drew.
  void notePaint(double offset) {
    if (_disposed) return;
    final previous = _lastOffset;
    _lastOffset = offset;
    if (previous != null && previous != offset) {
      _movedThisFrame = true;
      _noteActivity();
      return;
    }
    if (_prioritiseOnNextPaint && !_reportedMoving) {
      _prioritiseOnNextPaint = false;
      _atlas.prioritise(_visibleGlyphs());
    }
  }

  /// Reports "not moving" and stops. Call when the viewport leaves the tree; a
  /// pending callback then does nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _setMoving(moving: false);
  }

  void _noteActivity() {
    if (_disposed) return;
    _setMoving(moving: true);
    if (_checkScheduled) return;
    _checkScheduled = true;
    _binding
      ..addPostFrameCallback(_check)
      // Resting is only knowable one frame later, and an idle app draws none.
      ..ensureVisualUpdate();
  }

  void _check(Duration _) {
    _checkScheduled = false;
    if (_disposed) return;
    final moved = _movedThisFrame;
    _movedThisFrame = false;
    if (_dragging) return; // The finger lifting asks again.
    if (moved || _isAnimating()) {
      _noteActivity();
      return;
    }
    _setMoving(moving: false);
    _prioritiseOnNextPaint = false;
    _atlas.prioritise(_visibleGlyphs());
  }

  void _setMoving({required bool moving}) {
    if (_reportedMoving == moving) return;
    _reportedMoving = moving;
    _atlas.reportScrolling(scrolling: moving);
  }
}
