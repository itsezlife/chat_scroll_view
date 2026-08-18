import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Viewport-owned long-press and tap that drive [ChatSelectionController].
///
/// Message rows must not attach competing detectors. A host
/// [ChatSelectionController.spanYield] that returns `true` claims the
/// long-press so selection does not start.
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

  /// When true, the current pointer cancelled a fling and must not select.
  bool Function()? flingCancelSuppresses;

  LongPressGestureRecognizer? _longPress;
  TapGestureRecognizer? _tap;
  int? _pointerDownId;

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
  }

  void _ensureRecognizers() {
    _longPress ??= LongPressGestureRecognizer(debugOwner: debugOwner)
      ..onLongPress = _onLongPress;
    _tap ??= TapGestureRecognizer(debugOwner: debugOwner)..onTap = _onTap;
  }

  void _onLongPress() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final id = _pointerDownId;
    final selection = this.selection;
    if (id == null || selection == null) return;
    if (selection.spanYield?.call(id) ?? false) return;
    if (selection.isSelected(id)) return;
    HapticFeedback.vibrate();
    selection.startSelection(id);
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
