import 'dart:collection';
import 'dart:ui' show Offset;

import 'package:chat_scroll_view/src/chat_scroll/chat_selection_allowed.dart';
import 'package:flutter/foundation.dart'
    show Listenable, ValueListenable, ValueNotifier, VoidCallback;
import 'package:flutter/scheduler.dart';
import 'package:meta/meta.dart' show internal;

export 'package:chat_scroll_view/src/chat_scroll/chat_selection_allowed.dart';

/// Whole-message selection controller for the chat viewport.
///
/// Long press enters selection mode and selects the message.
/// Taps toggle messages. Selection mode exits when the set empties.
/// [selectionCap] optionally limits how large the selected set can grow.
/// [selectionAllowed] optionally controls per-id membership and chrome
/// (see [ChatSelectionAllowed]).
///
/// Lives outside the render tree — survives render eviction and can be
/// queried by external UI (toolbar, copy button). Implements [Listenable]
/// so the widget-based viewport can drive `ListenableBuilder` directly.
///
/// ### Swapping conversations
///
/// Selection is a bare `Set<int>` of message ids — it has no notion of
/// *which* conversation those ids belong to. When the consumer swaps the
/// `ChatDataSource` (e.g. opening a different chat thread on the same
/// viewport) the previously-selected ids stay in the set and will now
/// silently match unrelated messages in the new conversation. Call [clear]
/// from your own dataSource-swap logic, or scope a separate
/// [ChatSelectionController] per conversation, to avoid this footgun.
///
/// ### Changing [selectionAllowed]
///
/// Assigning [selectionAllowed] (or calling
/// [reapplySelectionAllowed]) drops any selected id that is no longer
/// selectable and notifies [addSelectionAllowedListener] so the
/// viewport can rebuild selection chrome. Mutating state closed over by the
/// predicate without reassigning or calling [reapplySelectionAllowed]
/// does not notify — chrome wrap may stay stale until the next natural
/// layout that re-evaluates selection-allowed.
class ChatSelectionController implements Listenable {
  final _selectedIds = HashSet<int>();
  final _capHits = ValueNotifier<int>(0);
  final _selectionAllowedListeners = <VoidCallback>[];

  /// Whether selection mode is active.
  bool get isSelectionMode => _selectedIds.isNotEmpty;

  /// The number of selected messages.
  int get count => _selectedIds.length;

  /// The set of selected message IDs (unmodifiable view).
  Set<int> get selectedIds => UnmodifiableSetView<int>(_selectedIds);

  /// Whether [messageId] is in the selection.
  bool isSelected(int messageId) => _selectedIds.contains(messageId);

  /// Enter selection mode and select [messageId].
  ///
  /// No-op when [messageId] is already selected, is not selectable, or when
  /// adding it would exceed [selectionCap].
  void startSelection(int messageId) {
    if (_selectedIds.contains(messageId)) return;
    if (!isSelectable(messageId)) return;
    if (isAtSelectionCap) {
      notifyCapHit();
      return;
    }
    _selectedIds.add(messageId);
    _notify();
  }

  /// Toggle [messageId] in/out of selection.
  /// Exits selection mode when the set becomes empty.
  ///
  /// Adding is a no-op when [messageId] is not selectable or the set is
  /// already at [selectionCap].
  void toggle(int messageId) {
    if (_selectedIds.remove(messageId)) {
      _notify();
      return;
    }
    if (!isSelectable(messageId)) return;
    if (isAtSelectionCap) {
      notifyCapHit();
      return;
    }
    _selectedIds.add(messageId);
    _notify();
  }

  /// Clear all selection. Exits selection mode.
  ///
  /// Visual chrome freezes selected-progress on each row and only animates
  /// mode closed — see [SelectableMessage]. This method just empties the set.
  void clear() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _notify();
  }

  /// Replaces the selected set with [ids]. No-op if equal. Empty [ids]
  /// exits selection mode. Ids that are not selectable are omitted.
  void replaceSelectedIds(Set<int> ids) {
    final next = _selectionAllowed == null
        ? ids
        : ids.where(isSelectable).toSet();
    if (next.length == _selectedIds.length && _selectedIds.containsAll(next)) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(next);
    _notify();
  }

  /// Optional maximum size of [selectedIds]. `null` (the default) means
  /// unlimited.
  ///
  /// A select span does not grow past this size. Unselect spans ignore it
  /// and may shrink the set while it is at the cap.
  int? selectionCap;

  /// Whether [count] has reached [selectionCap]. Always `false` when the
  /// cap is `null`.
  bool get isAtSelectionCap {
    final cap = selectionCap;
    return cap != null && _selectedIds.length >= cap;
  }

  /// Bumps whenever an add is refused because the set is already at
  /// [selectionCap]. The selected set does not change, so [addListener]
  /// on this controller does not fire — listen here to shake chrome or
  /// play an error haptic.
  ValueListenable<int> get capHits => _capHits;

  bool _capHitScheduled = false;

  /// Records a refused add at [selectionCap]. The viewport calls this
  /// when a select span cannot grow; hosts normally listen to [capHits]
  /// instead of calling this themselves.
  void notifyCapHit() {
    void bump() {
      if (_disposed) return;
      _capHits.value++;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_capHitScheduled) return;
      _capHitScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _capHitScheduled = false;
        bump();
      });
      return;
    }
    bump();
  }

  /// Host claim on a long-press that would start a span gesture.
  ///
  /// Called with the pressed [messageId] and the long-press **global** point.
  /// Return `true` to claim: the viewport does not start a span and does not
  /// change membership from that press. `null` (the default) never claims.
  ///
  /// MUST stay side-effect free — start text selection (or other host work)
  /// from [addSpanYieldedListener], not here. The viewport keeps the
  /// long-press; it does not forward the arena to a child.
  bool Function(int messageId, Offset globalOffset)? spanYield;

  final _spanYieldedListeners =
      <void Function(int messageId, Offset globalOffset)>[];

  /// Subscribe to a claimed [spanYield]. Payload matches the predicate call
  /// that returned `true`. Dedup-on-add; snapshot dispatch.
  ///
  /// Notified only when the viewport claims via [claimSpanYield] — a bare
  /// `true` from [spanYield] without that call does not notify. Post-
  /// [dispose] claims are silent.
  void addSpanYieldedListener(
    void Function(int messageId, Offset globalOffset) listener,
  ) {
    if (_spanYieldedListeners.contains(listener)) return;
    _spanYieldedListeners.add(listener);
  }

  /// Removes a listener registered with [addSpanYieldedListener].
  void removeSpanYieldedListener(
    void Function(int messageId, Offset globalOffset) listener,
  ) => _spanYieldedListeners.remove(listener);

  /// Runs [spanYield] at [globalOffset]. When claimed, notifies
  /// [addSpanYieldedListener] once and returns `true`. Otherwise `false`.
  ///
  /// Viewport selection pointer only. Hosts MUST listen via
  /// [addSpanYieldedListener] and start text selection from that notify —
  /// do not call this to simulate entry.
  @internal
  bool claimSpanYield(int messageId, Offset globalOffset) {
    if (_disposed) return false;
    if (!(spanYield?.call(messageId, globalOffset) ?? false)) return false;
    for (final cb in List.of(_spanYieldedListeners, growable: false)) {
      cb(messageId, globalOffset);
    }
    return true;
  }

  /// Host predicate: per-id membership and chrome grants.
  /// `null` (the default) is [ChatSelectionAllowed.full] for every
  /// present message. A non-selectable id is never a span hit and is omitted
  /// from the selection span. Chrome wrap follows
  /// [ChatSelectionAllowed.showsChrome].
  ///
  /// Assigning a new function (or `null`) re-filters [selectedIds] and
  /// notifies [addSelectionAllowedListener]. Prefer a new closure (or
  /// [reapplySelectionAllowed]) when closed-over host state changes.
  ChatSelectionAllowed Function(int messageId)?
  get selectionAllowed => _selectionAllowed;
  set selectionAllowed(
    ChatSelectionAllowed Function(int messageId)? value,
  ) {
    if (identical(_selectionAllowed, value)) return;
    _selectionAllowed = value;
    reapplySelectionAllowed();
  }

  ChatSelectionAllowed Function(int messageId)? _selectionAllowed;

  /// Resolved [ChatSelectionAllowed] for [messageId].
  /// [ChatSelectionAllowed.full] when [selectionAllowed] is null.
  ChatSelectionAllowed isSelectionAllowed(int messageId) =>
      _selectionAllowed?.call(messageId) ??
      ChatSelectionAllowed.full;

  /// Whether [messageId] may join the selected set.
  bool isSelectable(int messageId) => isSelectionAllowed(messageId).isSelectable;

  /// Re-runs [selectionAllowed] against [selectedIds] and notifies
  /// [addSelectionAllowedListener] without requiring a new function
  /// identity.
  ///
  /// Use when the predicate closes over mutable host state that changed
  /// in place and the host did not reassign [selectionAllowed].
  void reapplySelectionAllowed() {
    _notifySelectionAllowed();
    final next = _selectedIds.where(isSelectable).toSet();
    if (next.length == _selectedIds.length && _selectedIds.containsAll(next)) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(next);
    _notify();
  }

  /// Registers [listener] for [selectionAllowed] changes (assign or
  /// [reapplySelectionAllowed]). Dedup-on-add; snapshot dispatch.
  ///
  /// The selected-set [Listenable] does **not** fire when [selectedIds] is
  /// unchanged — listen here for chrome-wrap invalidation.
  void addSelectionAllowedListener(VoidCallback listener) {
    if (_selectionAllowedListeners.contains(listener)) return;
    _selectionAllowedListeners.add(listener);
  }

  /// Removes a listener registered with [addSelectionAllowedListener].
  void removeSelectionAllowedListener(VoidCallback listener) =>
      _selectionAllowedListeners.remove(listener);

  void _notifySelectionAllowed() {
    for (final cb in _selectionAllowedListeners.toList(growable: false)) {
      cb();
    }
  }

  // --- Listeners ---

  /// Plain `List` so the field's runtime type stays stable across hot-reload.
  /// `addListener` dedups explicitly so a double-registration with the same
  /// closure is a no-op — otherwise the symmetric `removeListener` only
  /// strips one of multiple registrations and the listener silently keeps
  /// firing for the rest of the controller's lifetime.
  final _listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  bool _notifyScheduled = false;

  void _notify() {
    // Span auto-scroll applies from performLayout. Listeners (composer,
    // chrome) call setState — illegal during persistentCallbacks. Same
    // trampoline as ChatScrollController.isAtTail.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (_disposed) return;
        _notifyNow();
      });
      return;
    }
    _notifyNow();
  }

  void _notifyNow() {
    // Iterate a snapshot: a listener may add/remove listeners while reacting
    // (e.g. a message widget unmounting during the resulting rebuild).
    for (final cb in _listeners.toList(growable: false)) {
      cb();
    }
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// Drop all listeners. Call from the owning widget's `dispose`. Idempotent
  /// — safe to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    _selectionAllowedListeners.clear();
    _spanYieldedListeners.clear();
    _capHits.dispose();
    // Drop the set: a stale reference held by a consumer (e.g. a toolbar
    // queueing an undo) must not silently match unrelated ids in a fresh
    // conversation that happens to reuse the same numeric range.
    _selectedIds.clear();
  }
}
