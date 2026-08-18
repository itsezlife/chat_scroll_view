import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
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
/// hit freezes the far end. Emptying the selected set does not end the
/// span — auto-scroll stays live until lift or cancel — but membership
/// stays empty; the live span does not paint new ids.
/// Pointer position during a live span is exposed so the viewport can
/// auto-scroll as the sole origin writer while the pointer sits in an
/// edge band.
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

  /// Fires when span liveness or the span pointer position changes so the
  /// viewport can start or stop origin auto-scroll.
  VoidCallback? onSpanSessionChanged;

  /// Whether a span session is live and has moved past slop.
  bool get isSpanLive => _spanOriginId != null && _spanPastSlop;

  /// Latest viewport-local pointer position during a live span.
  Offset? get spanPointerLocal => _spanPointerLocal;

  LongPressGestureRecognizer? _longPress;
  TapGestureRecognizer? _tap;
  int? _pointerDownId;
  int? _spanOriginId;
  Set<int>? _spanSnapshot;
  _SpanPolarity? _spanPolarity;
  bool _spanPastSlop = false;
  bool _spanMembershipFrozen = false;
  Offset? _spanPointerLocal;

  /// Forwards a down event to the selection recognizers when a loaded
  /// message is under the pointer.
  void addPointer(PointerDownEvent event) {
    if (selection == null) return;
    _pointerDownId = messageIdAt?.call(event.localPosition);
    _spanPointerLocal = event.localPosition;
    if (_pointerDownId == null) return;
    _ensureRecognizers();
    _longPress!.addPointer(event);
    _tap!.addPointer(event);
  }

  /// Drops recognizers. Safe to call twice.
  void dispose() {
    onSpanSessionChanged = null;
    _longPress?.dispose();
    _longPress = null;
    _tap?.dispose();
    _tap = null;
    _pointerDownId = null;
    _clearSpan();
  }

  /// Re-applies the live span at [local]. No-op when no span is live.
  void applySpanAt(Offset local) {
    _spanPointerLocal = local;
    if (!isSpanLive) return;
    _applySpanAt(local);
  }

  void _ensureRecognizers() {
    _longPress ??=
        LongPressGestureRecognizer(
            debugOwner: debugOwner,
            duration: ChatSelectionMetrics.longPressTimeout,
          )
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
    // Telegram keeps the rubber-band live even when this toggle emptied the
    // set (unselect of the last selected message). Auto-scroll must not die,
    // but membership stays frozen empty — no new ids.
    _spanOriginId = id;
    _spanSnapshot = Set<int>.of(selection.selectedIds);
    _spanPolarity = polarity;
    _spanMembershipFrozen = !selection.isSelectionMode;
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
    _spanPointerLocal = details.localPosition;
    if (!_spanPastSlop) {
      if (details.offsetFromOrigin.distance <= ChatSelectionMetrics.spanSlop) {
        return;
      }
      _spanPastSlop = true;
    }
    _applySpanAt(details.localPosition);
    onSpanSessionChanged?.call();
  }

  void _applySpanAt(Offset local) {
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
    if (_spanMembershipFrozen) return;
    final hit = (spanHitAt ?? messageIdAt)?.call(local);
    if (hit == null) return;
    final chain = spanChain?.call(origin, hit) ?? <int>[origin, hit];
    final next = switch (polarity) {
      _SpanPolarity.unselect => snapshot.difference(chain.toSet()),
      _SpanPolarity.select => {...snapshot, ...chain},
    };
    selection.replaceSelectedIds(next);
    if (next.isEmpty) _spanMembershipFrozen = true;
  }

  void _clearSpan() {
    final wasLive = _spanOriginId != null;
    _spanOriginId = null;
    _spanSnapshot = null;
    _spanPolarity = null;
    _spanPastSlop = false;
    _spanMembershipFrozen = false;
    _spanPointerLocal = null;
    if (wasLive) onSpanSessionChanged?.call();
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
