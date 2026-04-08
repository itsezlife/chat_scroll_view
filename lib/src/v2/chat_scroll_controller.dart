import 'package:flutter/foundation.dart';

/// Scroll controller for [ChatScrollView].
///
/// Owns anchor state (navigation) and boundary flags.
/// Uses typed listeners instead of [ChangeNotifier] —
/// subscribers know exactly what event occurred.
class ChatScrollController {
  // --- Jump: typed listener with payload ---

  final _jumpListeners = <ValueChanged<int>>[];

  /// Subscribe to jump events. Callback receives the target message ID.
  void addJumpListener(ValueChanged<int> callback) =>
      _jumpListeners.add(callback);

  /// Unsubscribe from jump events.
  void removeJumpListener(ValueChanged<int> callback) =>
      _jumpListeners.remove(callback);

  /// Jump to a specific message, resetting the anchor.
  void jumpTo(int messageId) {
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    for (final cb in _jumpListeners) {
      cb(messageId);
    }
  }

  // --- Boundary: typed listener ---

  final _boundaryListeners = <VoidCallback>[];

  /// Subscribe to boundary state changes.
  void addBoundaryListener(VoidCallback callback) =>
      _boundaryListeners.add(callback);

  /// Unsubscribe from boundary state changes.
  void removeBoundaryListener(VoidCallback callback) =>
      _boundaryListeners.remove(callback);

  void _notifyBoundary() {
    for (final cb in _boundaryListeners) {
      cb();
    }
  }

  /// Whether the oldest message in the conversation has been fetched.
  bool get reachedOldest => _reachedOldest;
  bool _reachedOldest = false;
  set reachedOldest(bool value) {
    if (_reachedOldest == value) return;
    _reachedOldest = value;
    _notifyBoundary();
  }

  /// Whether the newest message in the conversation has been fetched.
  bool get reachedNewest => _reachedNewest;
  bool _reachedNewest = false;
  set reachedNewest(bool value) {
    if (_reachedNewest == value) return;
    _reachedNewest = value;
    _notifyBoundary();
  }

  /// The ID of the oldest known message, if any.
  int? oldestKnownId;

  /// The ID of the newest known message, if any.
  int? newestKnownId;

  // --- Anchor state (read-only for public, writable for viewport) ---

  /// The message ID used as layout origin.
  int get anchorMessageId => _anchorMessageId;
  int _anchorMessageId = 0;

  /// Pixel offset of the anchor message's top edge from the viewport top.
  double get anchorPixelOffset => _anchorPixelOffset;
  double _anchorPixelOffset = 0.0;

  // --- Viewport-only: silent mutation without notifications ---

  /// Apply a scroll delta without notification.
  /// Called by the viewport from the Ticker callback.
  @internal
  void applyScrollDelta(double delta) {
    _anchorPixelOffset += delta;
  }

  /// Silently reassign anchor (no notification).
  /// Called by the viewport during anchor renormalization inside performLayout.
  @internal
  void reassignAnchor(int messageId, double pixelOffset) {
    _anchorMessageId = messageId;
    _anchorPixelOffset = pixelOffset;
  }
}
