import 'dart:collection';

import 'package:flutter/foundation.dart'
    show Listenable, ValueListenable, ValueNotifier, VoidCallback;
import 'package:flutter/scheduler.dart';

/// Whole-message selection controller for the chat viewport.
///
/// Long press enters selection mode and selects the message.
/// Taps toggle messages. Selection mode exits when the set empties.
/// [selectionCap] optionally limits how large the selected set can grow.
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
class ChatSelectionController implements Listenable {
  final _selectedIds = HashSet<int>();
  final _capHits = ValueNotifier<int>(0);

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
  /// No-op when [messageId] is already selected, or when adding it would
  /// exceed [selectionCap].
  void startSelection(int messageId) {
    if (_selectedIds.contains(messageId)) return;
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
  /// Adding is a no-op when the set is already at [selectionCap].
  void toggle(int messageId) {
    if (_selectedIds.remove(messageId)) {
      _notify();
      return;
    }
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
  /// exits selection mode.
  void replaceSelectedIds(Set<int> ids) {
    if (ids.length == _selectedIds.length && _selectedIds.containsAll(ids)) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(ids);
    _notify();
  }

  /// Optional maximum size of [selectedIds]. `null` (the default) means
  /// unlimited — the package does not hardcode Telegram's 100.
  ///
  /// A select span does not grow past this size. Unselect spans ignore it
  /// and may shrink the set while it is at the cap. Hosts that want
  /// Telegram's limit set this to `100`.
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

  /// Host claim on a long-press that would start a span.
  ///
  /// Return `true` to claim the press: selection mode does not start and the
  /// set stays empty. `null` (the default) never claims. This is the seam
  /// for a future in-bubble text selector; unused until that selector exists.
  bool Function(int messageId)? spanYield;

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
    _capHits.dispose();
    // Drop the set: a stale reference held by a consumer (e.g. a toolbar
    // queueing an undo) must not silently match unrelated ids in a fresh
    // conversation that happens to reuse the same numeric range.
    _selectedIds.clear();
  }
}
