import 'dart:collection';

import 'package:flutter/foundation.dart' show Listenable, VoidCallback;

/// Whole-message selection controller for the chat viewport.
///
/// Long press enters selection mode and selects the message.
/// Taps toggle messages. Selection mode exits when the set empties.
///
/// Lives outside the render tree — survives render eviction and can be
/// queried by external UI (toolbar, copy button). Implements [Listenable]
/// so the widget-based viewport can drive `ListenableBuilder` directly.
class ChatSelectionController implements Listenable {
  final _selectedIds = HashSet<int>();

  /// Whether selection mode is active.
  bool get isSelectionMode => _selectedIds.isNotEmpty;

  /// The number of selected messages.
  int get count => _selectedIds.length;

  /// The set of selected message IDs (unmodifiable view).
  Set<int> get selectedIds => UnmodifiableSetView<int>(_selectedIds);

  /// Whether [messageId] is in the selection.
  bool isSelected(int messageId) => _selectedIds.contains(messageId);

  /// Enter selection mode and select [messageId].
  void startSelection(int messageId) {
    if (!_selectedIds.add(messageId)) return;
    _notify();
  }

  /// Toggle [messageId] in/out of selection.
  /// Exits selection mode when the set becomes empty.
  void toggle(int messageId) {
    if (!_selectedIds.remove(messageId)) {
      _selectedIds.add(messageId);
    }
    _notify();
  }

  /// Clear all selection. Exits selection mode.
  void clear() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _notify();
  }

  // --- Listeners ---

  final _listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    // Iterate a snapshot: a listener may add/remove listeners while reacting
    // (e.g. a message widget unmounting during the resulting rebuild).
    for (final cb in _listeners.toList(growable: false)) {
      cb();
    }
  }

  /// Drop all listeners. Call from the owning widget's `dispose`.
  void dispose() => _listeners.clear();
}
