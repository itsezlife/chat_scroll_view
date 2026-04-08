import 'dart:collection';

import 'package:flutter/services.dart' show TextSelection;

/// Callback that receives the current selection state.
typedef ChatSelectionListener = void Function(
  Map<int, TextSelection?> selection,
);

/// Selection state for [ChatScrollView].
///
/// Holds a `Map<int, TextSelection?>` where:
/// - key = messageId
/// - value = [TextSelection] for text-range selection, or `null` for
///   whole-bubble selection
///
/// Lives outside the render tree — survives render eviction and can be
/// queried by external UI (toolbar, copy button).
class ChatSelectionController {
  final _selection = HashMap<int, TextSelection?>();
  late final _view = UnmodifiableMapView<int, TextSelection?>(_selection);
  final _listeners = <ChatSelectionListener>[];

  /// Current selection (unmodifiable view, zero-copy).
  Map<int, TextSelection?> get selection => _view;

  /// Whether any messages are selected.
  bool get hasSelection => _selection.isNotEmpty;

  /// Whether [messageId] is in the selection.
  bool isSelected(int messageId) => _selection.containsKey(messageId);

  // --- Mutation ---

  /// Select text range within a single message. Clears previous selection.
  void selectText(int messageId, TextSelection textSelection) {
    _selection
      ..clear()
      ..[messageId] = textSelection;
    _notify();
  }

  /// Select messages as whole bubbles. Clears previous selection.
  void selectBubbles(Iterable<int> messageIds) {
    _selection.clear();
    for (final id in messageIds) {
      _selection[id] = null;
    }
    _notify();
  }

  /// Toggle a single message in/out of bubble selection.
  void toggleBubble(int messageId) {
    if (_selection.containsKey(messageId)) {
      _selection.remove(messageId);
    } else {
      _selection[messageId] = null;
    }
    _notify();
  }

  /// Clear all selection.
  void clear() {
    if (_selection.isEmpty) return;
    _selection.clear();
    _notify();
  }

  // --- Typed listener ---

  void addListener(ChatSelectionListener cb) => _listeners.add(cb);
  void removeListener(ChatSelectionListener cb) => _listeners.remove(cb);

  void _notify() {
    for (final cb in _listeners) {
      cb(_view);
    }
  }
}
