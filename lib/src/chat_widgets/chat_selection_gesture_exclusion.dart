import 'package:flutter/foundation.dart';

/// Pointer ids for which the viewport must not arm **message selection**
/// gestures (pan / long-press / selection tap).
///
/// [ChatTapHighlight] registers on pointer-down when appropriate: always for
/// mouse/trackpad (desktop pan must not drag-select on chrome), and on touch
/// only when the host supplies [ChatTapHighlight.onLongPress] (absorb). Null
/// long-press on touch leaves the pointer alone so mobile **message selection**
/// can claim the press (e.g. sender-name chrome).
///
/// Hit-test dispatch reaches the leaf [Listener] before the viewport ancestor,
/// so exclusion is visible when selection [addPointer] runs. Prefer this over
/// a competing [PanGestureRecognizer] on chrome.
///
/// A second, narrower registry ([bar]) bars only the primary press, for
/// [ChatMessageTapBarrier].
abstract final class ChatSelectionGestureExclusion {
  static final Set<int> _pointers = <int>{};

  /// Excludes [pointer] from the next viewport selection [addPointer].
  static void exclude(int pointer) => _pointers.add(pointer);

  /// Returns whether [pointer] was excluded, and clears it.
  static bool take(int pointer) => _pointers.remove(pointer);

  static final Set<int> _barred = <int>{};

  /// Bars [pointer]'s **primary** press from the message under it, for the
  /// next viewport selection [addPointer]: no pan, long-press, text-selection
  /// arming, inline hit, message selection toggle or idle message tap.
  ///
  /// Unlike [exclude] the pointer is still handed to the tap recognizer, so a
  /// secondary click reaches the secondary message tap and a tap still
  /// dismisses a live **text selection**. See [ChatMessageTapBarrier].
  static void bar(int pointer) => _barred.add(pointer);

  /// Returns whether [pointer] was barred by [bar], and clears it.
  static bool takeBarred(int pointer) => _barred.remove(pointer);

  /// Drops all exclusions. Tests only.
  @visibleForTesting
  static void debugReset() {
    _pointers.clear();
    _barred.clear();
  }
}
