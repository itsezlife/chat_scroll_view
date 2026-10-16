import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';

/// Turns the viewport's motion events into the two facts a background
/// producer wants: **is the catalogue moving**, and, once it stops, **what is
/// on screen**.
///
/// The producer is a page-level baker that must neither compete with motion
/// nor bake the wrong page first. It does not read motion events; it reads
/// what this class publishes on the same stream:
///
/// - [PanelCatalogScrollingChanged] `true` at once when the catalogue starts
///   to move, and `false` only after a whole frame passed with nothing moving;
/// - [PanelCatalogScrollSettled] with the visible keys, right after that
///   `false` event, and again when a new snapshot changes what is on screen
///   while nothing moves.
///
/// ## What counts as moving
///
/// - an offset write: [PanelCatalogViewportScrolled] (drag, wheel, fling
///   ticks), [PanelCatalogOffsetChanged] (animation and stitch ticks, jumps),
///   [PanelCatalogProgrammaticJump];
/// - a drag in progress, from [PanelCatalogUserDragStart] until
///   [PanelCatalogUserDragEnd] or [PanelCatalogUserDragCancel]: a finger that
///   holds still after dragging is not a frame without motion, so the bake
///   stays paused until the finger lifts;
/// - the viewport saying it is mid-fling, mid-jump or mid-stitch
///   ([isAnimating] is asked first, so a rest between two ticks of an
///   animation is not mistaken for settling);
/// - the start of a fling, animation or section jump.
///
/// Nothing here holds a timer. The only pending work is one post-frame
/// callback while the catalogue moves, and none when it rests.
final class CatalogBakeActivity {
  /// Creates the reporter. It listens to [events] and publishes through
  /// [publish], which must deliver to the same stream.
  ///
  /// [isAnimating] says whether the viewport is mid-fling or mid-jump;
  /// [visibleKeys] lists the leaves on screen, top first.
  CatalogBakeActivity({
    required EventObservable<PanelCatalogScrollEvent> events,
    required void Function(PanelCatalogScrollEvent event) publish,
    required bool Function() isAnimating,
    required List<ContentKey> Function() visibleKeys,
    SchedulerBinding? binding,
  }) : _events = events,
       _publish = publish,
       _isAnimating = isAnimating,
       _visibleKeys = visibleKeys,
       _binding = binding ?? SchedulerBinding.instance {
    _events.addListener(_onEvent);
  }

  final EventObservable<PanelCatalogScrollEvent> _events;
  final void Function(PanelCatalogScrollEvent event) _publish;
  final bool Function() _isAnimating;
  final List<ContentKey> Function() _visibleKeys;
  final SchedulerBinding _binding;

  bool _movedThisFrame = false;
  bool _dragging = false;
  bool _reportedMoving = false;
  bool _checkScheduled = false;
  bool _settleOnNextPaint = true;
  bool _disposed = false;

  /// Whether the last published [PanelCatalogScrollingChanged] said moving.
  bool get isMoving => _reportedMoving;

  /// The slots changed, so what is on screen may have too: say so at the next
  /// paint that is not a scroll.
  void visibleBandChanged() => _settleOnNextPaint = true;

  /// Called from every paint.
  void notePaint() {
    if (_disposed) return;
    if (_settleOnNextPaint && !_reportedMoving) {
      _settleOnNextPaint = false;
      _publishSettled();
    }
  }

  /// Reports "not moving" and stops listening. Call when the viewport leaves
  /// the tree; a pending callback then does nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.removeListener(_onEvent);
    _setMoving(moving: false);
  }

  void _onEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogUserDragStart():
        _dragging = true;
        _noteActivity();
      case PanelCatalogUserDragEnd() || PanelCatalogUserDragCancel():
        if (!_dragging) break;
        _dragging = false;
        _noteActivity();
      case PanelCatalogViewportScrolled() ||
          PanelCatalogOffsetChanged() ||
          PanelCatalogProgrammaticJump():
        _movedThisFrame = true;
        _noteActivity();
      case PanelCatalogFlingStart() ||
          PanelCatalogAnimateStart() ||
          PanelCatalogSectionJumpStart():
        _noteActivity();
      case PanelCatalogFlingEnd() ||
          PanelCatalogAnimateEnd() ||
          PanelCatalogSectionJumpEnd() ||
          PanelCatalogScrollingChanged() ||
          PanelCatalogScrollSettled():
        break;
    }
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
    _settleOnNextPaint = false;
    _publishSettled();
  }

  void _setMoving({required bool moving}) {
    if (_reportedMoving == moving) return;
    _reportedMoving = moving;
    _publish(PanelCatalogScrollingChanged(scrolling: moving));
  }

  void _publishSettled() => _publish(PanelCatalogScrollSettled(_visibleKeys()));
}
