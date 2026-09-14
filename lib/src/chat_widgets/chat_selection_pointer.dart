import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Viewport-owned long-press, tap, and selection span that drive
/// [ChatSelectionController].
///
/// Message rows must not attach competing detectors. Under mobile
/// [ChatSelectionPolicy], when a pointer-down would route to **text selection**
/// ([ChatSelectionController.shouldRouteLongPressToText] — already-selected
/// body text), the viewport **yields**: it does not register its long-press
/// for that pointer, so the per-body markdown selection scope owns the
/// continuous press (ADR 015). Unyielded long-presses start a **span gesture**.
/// After an unrouted long-press, polarity is
/// locked at start: an unselected origin starts a select span; a selected
/// origin toggles off and starts an unselect span. A null span hit freezes the far end.
/// Emptying the selected set does not end the span — auto-scroll stays live
/// until lift or cancel — but membership stays empty; the live span does
/// not paint new ids. Pointer position during a live span is exposed so the
/// viewport can auto-scroll as the sole origin writer while the pointer sits
/// in an edge band. [abortSpan] ends the session without clearing the
/// selected set — used when the gesture origin becomes absent.
///
/// When **text selection** is active ([ChatSelectionController.isTextSelectionActive]),
/// an idle tap dismisses text selection ([ChatSelectionController.clearTextSelection])
/// without toggling message selection membership or dispatching [onIdleMessageTap].
/// Under mobile policy, all previously selected messages remain selected; under
/// desktop/web policy, message membership remains empty. [onIdleMessageTap] is
/// mutually exclusive with both message selection and text selection. When text
/// selection is active, taps anywhere in the viewport (including empty padding
/// where no message is hit) dismiss text chrome.
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

  /// Idle message tap in viewport-local coordinates. Fired when the tap
  /// won the arena, fling-cancel does not suppress, and message selection
  /// is inactive. Null is a no-op.
  void Function(int id, Offset localPosition)? onIdleMessageTap;

  /// Secondary message tap (right-click) in viewport-local coordinates. Fired
  /// when secondary tap won the arena and fling-cancel does not suppress.
  /// Null is a no-op — and the secondary recognizer is not armed, so
  /// per-body text context menus can win the arena.
  void Function(int id, Offset localPosition)? get onSecondaryMessageTap =>
      _onSecondaryMessageTap;
  set onSecondaryMessageTap(void Function(int id, Offset localPosition)? value) {
    if (identical(_onSecondaryMessageTap, value)) return;
    _onSecondaryMessageTap = value;
    // Keep the live recognizer in sync without waiting for the next down.
    _tap?.onSecondaryTapUp = value == null ? null : _onSecondaryTapUp;
  }

  void Function(int id, Offset localPosition)? _onSecondaryMessageTap;

  /// Fires when span liveness or the span pointer position changes so the
  /// viewport can start or stop origin auto-scroll.
  VoidCallback? onSpanSessionChanged;

  /// Whether a span session is live and has moved past slop, or an uncommitted
  /// drag selection is actively tracking on desktop.
  bool get isSpanLive =>
      (_spanOriginId != null && _spanPastSlop) ||
      (_panOriginId != null && (selection?.hasDragSelection ?? false));

  /// Gesture origin of the current span session, if any.
  int? get spanOriginId => _spanOriginId;

  /// Latest viewport-local pointer position during a live span.
  Offset? get spanPointerLocal => _spanPointerLocal;

  LongPressGestureRecognizer? _longPress;
  PanGestureRecognizer? _pan;
  TapGestureRecognizer? _tap;
  int? _pointerDownId;
  Offset? _pointerDownLocal;
  Offset? _pointerDownGlobal;
  int? _spanOriginId;
  int? _panOriginId;
  Offset? _panStartLocal;
  ChatDragSelectAction _panAction = ChatDragSelectAction.none;
  Set<int>? _spanSnapshot;
  _SpanPolarity? _spanPolarity;
  bool _spanPastSlop = false;
  bool _spanMembershipFrozen = false;
  Offset? _spanPointerLocal;
  int? _spanHitId;
  bool _spanCapHitSent = false;

  /// Forwards a down event to the selection recognizers when a loaded
  /// message is under the pointer, or when text selection is active so an
  /// idle tap outside loaded messages can dismiss text chrome.
  void addPointer(PointerDownEvent event) {
    if (selection == null &&
        onIdleMessageTap == null &&
        _onSecondaryMessageTap == null) {
      return;
    }
    _pointerDownId = messageIdAt?.call(event.localPosition);
    _pointerDownLocal = event.localPosition;
    _pointerDownGlobal = event.position;
    _spanPointerLocal = event.localPosition;
    if (_pointerDownId == null) {
      if (selection case final sel? when sel.isTextSelectionActive) {
        _ensureRecognizers();
        _tap?.addPointer(event);
      }
      return;
    }
    _ensureRecognizers();
    if (selection != null) {
      final policy =
          selection?.selectionPolicy ?? const ChatSelectionPolicy.mobile();
      if (policy.usesTimerBasedLongPress) {
        final sel = selection!;
        final id = _pointerDownId!;
        // Yield the long-press when this hit would route to text so the
        // per-body markdown scope owns the continuous press (ADR 015).
        if (!sel.shouldRouteLongPressToText(id, event.position)) {
          _longPress?.addPointer(event);
        }
      } else {
        final sel = selection!;
        final id = _pointerDownId!;
        final landsOnText = sel.containsGlobal(id, event.position);
        if (sel.isTextSelectionActive) {
          // Inside the body: markdown / idle tap own dismiss and text drag.
          // Outside (padding, sibling chrome, Text-only rows): keep message
          // pan so drag-out can promote to message selection (tdesktop
          // PrepareSelect when not PointState::Inside).
          if (!landsOnText) {
            _pan?.addPointer(event);
          }
        } else if (landsOnText &&
            !sel.isSelectionMode &&
            policy.allowsTextEntryWithoutMessageSelection) {
          // Surface bounds (bubble Inside), not glyph ink — padding / empty
          // line gutter arms text; outside the body → message pan.
          sel.armTextSelection(id);
        } else {
          _pan?.addPointer(event);
        }
      }
    }
    _tap?.addPointer(event);
  }

  /// Drops recognizers. Safe to call twice.
  void dispose() {
    onSpanSessionChanged = null;
    onIdleMessageTap = null;
    _onSecondaryMessageTap = null;
    _tap?.onSecondaryTapUp = null;
    _longPress?.dispose();
    _longPress = null;
    _pan?.dispose();
    _pan = null;
    _tap?.dispose();
    _tap = null;
    _pointerDownId = null;
    _pointerDownLocal = null;
    _pointerDownGlobal = null;
    _panOriginId = null;
    _clearSpan();
  }

  /// Re-applies the live span at [local]. No-op when no span is live.
  void applySpanAt(Offset local) {
    _spanPointerLocal = local;
    if (!isSpanLive) return;
    _applySpanAt(local);
  }

  /// Ends the span session and keeps the selected set. No-op when idle.
  /// Does not pick a new gesture origin.
  void abortSpan() => _clearSpan();

  /// Whether auto-scroll in [edgeDirection] would add a **new** id to a
  /// select span that is already at [ChatSelectionController.selectionCap].
  ///
  /// False while the current span hit is already selected — scrolling over
  /// members is not a refused add. Unselect spans always return `false`.
  bool selectSpanGrowthBlocked(int edgeDirection) {
    if (_spanPolarity != _SpanPolarity.select) return false;
    final selection = this.selection;
    if (selection == null || !selection.isAtSelectionCap) return false;
    final origin = _spanOriginId;
    final hit = _spanHitId;
    if (origin == null || hit == null) return false;
    if (selection.isSelected(hit)) return false;
    if (hit == origin) return false;
    if (hit < origin) return edgeDirection > 0;
    return edgeDirection < 0;
  }

  /// Records a cap hit when grow-direction auto-scroll is blocked. Once
  /// per wall — further blocked ticks are silent until the span shrinks.
  void notifyGrowBlocked() {
    if (_spanPolarity != _SpanPolarity.select) return;
    final selection = this.selection;
    if (selection == null || !selection.isAtSelectionCap) return;
    if (_spanCapHitSent) return;
    _spanCapHitSent = true;
    selection.notifyCapHit();
  }

  void _ensureRecognizers() {
    final policy =
        selection?.selectionPolicy ?? const ChatSelectionPolicy.mobile();
    if (policy.usesTimerBasedLongPress) {
      _pan?.dispose();
      _pan = null;
      _longPress ??=
          LongPressGestureRecognizer(
              debugOwner: debugOwner,
              duration: ChatSelectionMetrics.longPressTimeout,
            )
            ..onLongPressStart = _onLongPressStart
            ..onLongPressMoveUpdate = _onLongPressMoveUpdate
            ..onLongPressEnd = (_) {
              _clearSpan();
            }
            ..onLongPressCancel = _onLongPressCancel;
    } else {
      _longPress?.dispose();
      _longPress = null;
      _pan ??=
          PanGestureRecognizer(debugOwner: debugOwner)
            ..onStart = _onPanStart
            ..onUpdate = _onPanUpdate
            ..onEnd = _onPanEnd
            ..onCancel = _onPanCancel;
    }
    _tap ??=
        TapGestureRecognizer(debugOwner: debugOwner)..onTap = _onTap;
    // Arm secondary only when the host opted in. Otherwise leave the arena
    // to per-body markdown so Flutter’s text context menu remains.
    _tap!.onSecondaryTapUp = _onSecondaryMessageTap == null
        ? null
        : _onSecondaryTapUp;
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    if (flingCancelSuppresses?.call() ?? false) return;
    final id = _pointerDownId;
    if (id == null) return;
    _onSecondaryMessageTap?.call(id, details.localPosition);
  }

  void _onPanStart(DragStartDetails details) {
    if (flingCancelSuppresses?.call() ?? false) return;
    final id = _pointerDownId;
    final selection = this.selection;
    if (id == null || selection == null) return;
    if (!selection.isSelectable(id)) return;

    _panOriginId = id;
    _spanPointerLocal = details.localPosition;
    _panStartLocal = _pointerDownLocal ?? details.localPosition;

    final isSelected = selection.isSelected(id);
    _panAction = isSelected
        ? ChatDragSelectAction.deselecting
        : ChatDragSelectAction.selecting;

    final hit = (spanHitAt ?? messageIdAt)?.call(details.localPosition) ?? id;
    final chain = spanChain?.call(id, hit) ?? <int>[id];
    selection.updateDragSelection(chain.toSet(), action: _panAction);
    onSpanSessionChanged?.call();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final selection = this.selection;
    if (selection == null) return;
    _spanPointerLocal = details.localPosition;

    if (_spanOriginId != null) {
      _applySpanAt(details.localPosition);
      onSpanSessionChanged?.call();
      return;
    }

    final origin = _panOriginId;
    if (origin == null) return;

    final startLocal = _panStartLocal;
    final hit = (spanHitAt ?? messageIdAt)?.call(details.localPosition);

    // If returned within drag slop of the press position, clear preview.
    // Uses vertical dy delta along the scroll axis so horizontal pointer drift
    // does not prevent clearing preview when returning to the origin.
    if (hit == origin && startLocal != null) {
      final delta = (details.localPosition.dy - startLocal.dy).abs();
      if (delta < ChatSelectionMetrics.spanSlop) {
        if (selection.hasDragSelection) {
          selection.clearDragSelection();
          onSpanSessionChanged?.call();
        }
        return;
      }
    }

    if (hit != null) {
      final chain = spanChain?.call(origin, hit) ?? <int>[origin, hit];
      selection.updateDragSelection(chain.toSet(), action: _panAction);
      onSpanSessionChanged?.call();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final selection = this.selection;
    if (_spanOriginId != null) {
      _clearSpan();
      return;
    }

    final origin = _panOriginId;
    _panOriginId = null;
    _panStartLocal = null;
    _panAction = ChatDragSelectAction.none;
    if (selection == null || origin == null) {
      _clearSpan();
      return;
    }

    if (selection.hasDragSelection) {
      selection.applyDragSelection();
    } else {
      selection.clearDragSelection();
    }
    _clearSpan();
  }

  void _onPanCancel() {
    _panOriginId = null;
    _panStartLocal = null;
    _panAction = ChatDragSelectAction.none;
    selection?.clearDragSelection();
    selection?.abortSpanFeedback();
    _clearSpan();
  }

  /// Arena / pointer cancel before or during long-press — drop membership
  /// preview and abort any armed tap-highlight ink immediately.
  void _onLongPressCancel() {
    selection?.abortSpanFeedback();
    _clearSpan();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (flingCancelSuppresses?.call() ?? false) return;
    final id = _pointerDownId;
    final selection = this.selection;
    if (id == null || selection == null) return;
    // Check for inline hit (e.g. long-press on a hyperlink).
    // The host may handle link long-press (e.g. preview sheet) instead of entering selection.
    final inlineHit = selection.resolveInlineHit(id, details.globalPosition);
    if (inlineHit != null && selection.handleInlineHitLongPress(inlineHit)) {
      // Code hold-to-copy aborts ink inside the facade. Link long-press keeps
      // press ink until pointer up.
      return;
    }
    if (inlineHit != null) {
      // Unclaimed inline long-press (suppressed code / no link handler):
      // abort ink so message / text selection can own the pointer.
      selection.abortSpanFeedback();
    }

    if (!selection.isSelectable(id)) return;

    // Subject-only surfaces while text is live: sibling scopes are off.
    // Body hit → retarget via facade. Padding / chrome → unselect span.
    if (selection.isTextSelectionActive &&
        selection.isSelected(id) &&
        selection.textSelectionSubject != id &&
        selection.containsGlobal(id, details.globalPosition)) {
      selection.abortSpanFeedback();
      selection.enterTextSelection(id, globalOffset: details.globalPosition);
      return;
    }

    selection.abortSpanFeedback();
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
    // Keeps the rubber-band live even when this toggle emptied the
    // set (unselect of the last selected message). Auto-scroll must not die,
    // but membership stays frozen empty — no new ids.
    _spanOriginId = id;
    _spanSnapshot = Set<int>.of(selection.selectedIds);
    _spanPolarity = polarity;
    _spanMembershipFrozen = !selection.isSelectionMode;
    _spanHitId = id;
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
      _SpanPolarity.select => _selectSpanIds(
        snapshot,
        chain,
        selection.selectionCap,
      ),
    };
    _spanHitId = hit;
    if (polarity == _SpanPolarity.select) {
      final uncapped =
          snapshot.length + chain.where((id) => !snapshot.contains(id)).length;
      if (selection.selectionCap != null && uncapped > next.length) {
        if (!_spanCapHitSent) {
          _spanCapHitSent = true;
          selection.notifyCapHit();
        }
      } else if (!selection.isAtSelectionCap) {
        _spanCapHitSent = false;
      }
    }
    selection.replaceSelectedIds(next);
    if (next.isEmpty) _spanMembershipFrozen = true;
  }

  void _clearSpan() {
    final wasLive = _spanOriginId != null || _panOriginId != null;
    _spanOriginId = null;
    _panOriginId = null;
    _panStartLocal = null;
    _panAction = ChatDragSelectAction.none;
    _spanSnapshot = null;
    _spanPolarity = null;
    _spanPastSlop = false;
    _spanMembershipFrozen = false;
    _spanPointerLocal = null;
    _spanHitId = null;
    _spanCapHitSent = false;
    if (wasLive) onSpanSessionChanged?.call();
  }

  void _onTap() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final selection = this.selection;
    final id = _pointerDownId;
    final global = _pointerDownGlobal;
    if (selection != null && id != null && global != null) {
      final hit = selection.resolveInlineHit(id, global);
      if (hit != null && selection.handleInlineHit(hit)) {
        return;
      }
    }
    if (selection case final sel? when sel.isTextSelectionActive) {
      sel.clearTextSelection();
      return;
    }
    if (id == null) return;
    if (selection case final sel? when sel.isSelectionMode) {
      if (!sel.isSelectable(id)) return;
      sel.toggle(id);
      return;
    }
    final local = _pointerDownLocal;
    if (local == null) return;
    final policy =
        selection?.selectionPolicy ?? const ChatSelectionPolicy.mobile();
    if (!policy.routesPrimaryTapToIdleMessage) return;
    onIdleMessageTap?.call(id, local);
  }
}

enum _SpanPolarity { select, unselect }

/// [snapshot] plus [chain] from origin toward the hit, stopping at [cap].
/// A null [cap] takes the full union.
Set<int> _selectSpanIds(Set<int> snapshot, List<int> chain, int? cap) {
  if (cap == null) return {...snapshot, ...chain};
  final next = Set<int>.of(snapshot);
  for (final id in chain) {
    if (next.contains(id)) continue;
    if (next.length >= cap) break;
    next.add(id);
  }
  return next;
}
