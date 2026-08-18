import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Viewport-owned long-press, tap, and selection span that drive
/// [ChatSelectionController].
///
/// Message rows must not attach competing detectors. A host
/// [ChatSelectionController.spanYield] that returns `true` claims the
/// long-press so selection does not start. After an unclaimed long-press,
/// polarity is locked at start: an unselected origin starts a select span;
/// a selected origin toggles off and starts an unselect span. A null span
/// hit freezes the far end. Emptying the selected set ends the span.
class ChatSelectionPointer {
  /// Creates recognizers owned by [debugOwner] (the viewport render object).
  ChatSelectionPointer({required this.debugOwner});

  /// Gesture debug owner — the viewport render object.
  final Object debugOwner;

  /// Selected-set seam. Null when the host did not wire selection.
  ChatSelectionController? selection;

  /// Resolves the loaded message under a viewport-local position, or `null`
  /// when the pointer is not over a loaded message body.
  int? Function(Offset localPosition)? messageIdAt;

  /// Span hit after clamping into the scroll band. Null freezes the far end.
  int? Function(Offset localPosition)? spanHitAt;

  /// Loaded present ids from [origin] to [hit], inclusive. The pointer
  /// applies span polarity against the selection snapshot; this callback
  /// does not apply span-eligibility itself.
  List<int> Function(int origin, int hit)? spanChain;

  /// When true, the current pointer cancelled a fling and must not select.
  bool Function()? flingCancelSuppresses;

  LongPressGestureRecognizer? _longPress;
  TapGestureRecognizer? _tap;
  int? _pointerDownId;
  int? _spanOriginId;
  Set<int>? _spanSnapshot;
  _SpanPolarity? _spanPolarity;
  bool _spanPastSlop = false;

  /// Forwards a down event to the selection recognizers when a loaded
  /// message is under the pointer.
  void addPointer(PointerDownEvent event) {
    if (selection == null) return;
    _pointerDownId = messageIdAt?.call(event.localPosition);
    if (_pointerDownId == null) return;
    _ensureRecognizers();
    _longPress!.addPointer(event);
    _tap!.addPointer(event);
  }

  /// Drops recognizers. Safe to call twice.
  void dispose() {
    _longPress?.dispose();
    _longPress = null;
    _tap?.dispose();
    _tap = null;
    _pointerDownId = null;
    _clearSpan();
  }

  void _ensureRecognizers() {
    _longPress ??= LongPressGestureRecognizer(debugOwner: debugOwner)
      ..onLongPress = _onLongPress
      ..onLongPressMoveUpdate = _onLongPressMoveUpdate
      ..onLongPressEnd = (_) {
        _clearSpan();
      }
      ..onLongPressCancel = _clearSpan;
    _tap ??= TapGestureRecognizer(debugOwner: debugOwner)..onTap = _onTap;
  }

  void _onLongPress() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final id = _pointerDownId;
    final selection = this.selection;
    if (id == null || selection == null) return;
    if (selection.spanYield?.call(id) ?? false) return;
    HapticFeedback.vibrate();
    final polarity = selection.isSelected(id)
        ? _SpanPolarity.unselect
        : _SpanPolarity.select;
    switch (polarity) {
      case _SpanPolarity.unselect:
        selection.toggle(id);
      case _SpanPolarity.select:
        selection.startSelection(id);
    }
    if (!selection.isSelectionMode) return;
    _spanOriginId = id;
    _spanSnapshot = Set<int>.of(selection.selectedIds);
    _spanPolarity = polarity;
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final origin = _spanOriginId;
    final snapshot = _spanSnapshot;
    final polarity = _spanPolarity;
    final selection = this.selection;
    if (origin == null ||
        snapshot == null ||
        polarity == null ||
        selection == null) {
      return;
    }
    if (!_spanPastSlop) {
      if (details.offsetFromOrigin.distance <= kTouchSlop) return;
      _spanPastSlop = true;
    }
    final hit = (spanHitAt ?? messageIdAt)?.call(details.localPosition);
    if (hit == null) return;
    final chain = spanChain?.call(origin, hit) ?? <int>[origin, hit];
    final next = switch (polarity) {
      _SpanPolarity.unselect => snapshot.difference(chain.toSet()),
      _SpanPolarity.select => {...snapshot, ...chain},
    };
    selection.replaceSelectedIds(next);
    if (next.isEmpty) _clearSpan();
  }

  void _clearSpan() {
    _spanOriginId = null;
    _spanSnapshot = null;
    _spanPolarity = null;
    _spanPastSlop = false;
  }

  void _onTap() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final id = _pointerDownId;
    final selection = this.selection;
    if (id == null || selection == null) return;
    if (!selection.isSelectionMode) return;
    selection.toggle(id);
  }
}

enum _SpanPolarity { select, unselect }
