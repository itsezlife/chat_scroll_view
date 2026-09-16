import 'package:flutter/foundation.dart';

/// Pointer ids for which the viewport must not arm **message selection**
/// gestures (pan / long-press / selection tap).
///
/// [ChatTapHighlight] registers on pointer-down when appropriate: always for
/// mouse/trackpad (desktop pan must not drag-select on chrome), and on touch
/// only when the host supplies [ChatTapHighlight.onLongPress] (absorb). Null
/// long-press on touch leaves the pointer alone so mobile **message selection**
/// can claim the press (Telegram sender-name chrome).
///
/// Hit-test dispatch reaches the leaf [Listener] before the viewport ancestor,
/// so exclusion is visible when selection [addPointer] runs. Prefer this over
/// a competing [PanGestureRecognizer] on chrome.
abstract final class ChatSelectionGestureExclusion {
  static final Set<int> _pointers = <int>{};

  /// Excludes [pointer] from the next viewport selection [addPointer].
  static void exclude(int pointer) => _pointers.add(pointer);

  /// Returns whether [pointer] was excluded, and clears it.
  static bool take(int pointer) => _pointers.remove(pointer);

  /// Drops all exclusions. Tests only.
  @visibleForTesting
  static void debugReset() => _pointers.clear();
}
