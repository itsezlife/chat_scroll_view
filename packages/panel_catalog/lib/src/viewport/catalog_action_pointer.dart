import 'package:flutter/gestures.dart';

/// Viewport-owned tap recognizer for the trailing action of a section header.
///
/// Does **not** own hit-testing ([actionAt] is supplied by the render object),
/// the action's geometry or scroll drag. A tap that begins on an action's hit
/// area and ends on it reports `(sectionId, actionId)`; a pointer that starts
/// a drag loses the arena to the scroll recognizer and reports nothing, so a
/// header with an action still scrolls.
///
/// Call [addPointer] from the render object's [PointerDownEvent] path only for
/// a pointer that landed on no leaf. The recognizer exists only while
/// [onSectionAction] is wired.
final class CatalogActionPointer {
  /// Creates a recognizer owned by [debugOwner] (the viewport render object).
  CatalogActionPointer({required this.debugOwner});

  /// Gesture debug owner: the viewport render object.
  final Object debugOwner;

  /// Resolves the action under a viewport-local position, or null when the
  /// point is on no action.
  (String sectionId, String actionId)? Function(Offset localPosition)? actionAt;

  /// The shell's reaction to a tapped action. Null disables recognition.
  void Function(String sectionId, String actionId)? onSectionAction;

  /// When true, a tap is silent: the pointer that only stopped a coasting
  /// fling.
  bool Function()? flingCancelSuppresses;

  TapGestureRecognizer? _tap;
  (String, String)? _down;

  /// Registers the tap recognizer for [event] when an action is under it.
  void addPointer(PointerDownEvent event) {
    if (onSectionAction == null) return;
    final hit = actionAt?.call(event.localPosition);
    if (hit == null) return;
    _down = hit;
    (_tap ??= TapGestureRecognizer(
      debugOwner: debugOwner,
    )..onTap = _onTap).addPointer(event);
  }

  /// Drops the recognizer. Safe to call twice.
  void dispose() {
    onSectionAction = null;
    actionAt = null;
    flingCancelSuppresses = null;
    _tap?.dispose();
    _tap = null;
    _down = null;
  }

  void _onTap() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final down = _down;
    final report = onSectionAction;
    if (down == null || report == null) return;
    report(down.$1, down.$2);
  }
}
