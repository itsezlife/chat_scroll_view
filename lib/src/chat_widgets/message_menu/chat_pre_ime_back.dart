import 'dart:async';

import 'package:flutter/foundation.dart';

/// Host-owned native intercept for Android back before the IME.
///
/// The package calls [acquire] when the first [ChatPreImeBackClaim] is
/// pushed and [release] when the last claim is popped. Incoming native
/// back is delivered to the top claim via
/// [ChatPreImeBackBinding.handleNativeBack] — this interface is not a
/// single overwriting callback slot.
abstract interface class ChatPreImeBackNative {
  /// Start intercepting Android back before the IME.
  Future<void> acquire();

  /// Stop intercepting.
  Future<void> release();
}

/// Process-wide binding for pre-IME back claims.
///
/// Assign [native] once at app startup. Null means Dart overlay back
/// only (desktop, tests, hosts without an Activity intercept).
abstract final class ChatPreImeBackBinding {
  /// Host native adapter. Null = no native intercept.
  static ChatPreImeBackNative? native;

  /// Delivers a native pre-IME back to the top claim.
  ///
  /// The host adapter calls this when Android dispatches back before
  /// the IME. Returns whether a claim handled it.
  static Future<bool> handleNativeBack() =>
      ChatPreImeBackClaim.handleNativeBack();

  /// Drops all claims and the native adapter. Tests only.
  @visibleForTesting
  static void debugReset() {
    ChatPreImeBackClaim.debugReset();
    native = null;
  }
}

/// One stacked claim on Android back before the IME.
///
/// Push on message-menu session start; [pop] on session end. The top
/// claim receives [ChatPreImeBackBinding.handleNativeBack]. Native
/// [ChatPreImeBackNative.acquire] runs only while the stack is
/// non-empty.
final class ChatPreImeBackClaim {
  ChatPreImeBackClaim._(this._onBack);

  final ValueGetter<Future<bool>> _onBack;
  var _popped = false;

  static final List<ChatPreImeBackClaim> _stack = <ChatPreImeBackClaim>[];

  /// Pushes [onBack] as the new top claim.
  static ChatPreImeBackClaim push(ValueGetter<Future<bool>> onBack) {
    final claim = ChatPreImeBackClaim._(onBack);
    _stack.add(claim);
    if (_stack.length == 1) {
      unawaited(
        ChatPreImeBackBinding.native?.acquire() ?? Future<void>.value(),
      );
    }
    return claim;
  }

  /// Pops this claim if it is still on the stack.
  void pop() {
    if (_popped) return;
    _popped = true;
    final removed = _stack.remove(this);
    if (!removed) return;
    if (_stack.isEmpty) {
      unawaited(
        ChatPreImeBackBinding.native?.release() ?? Future<void>.value(),
      );
    }
  }

  /// Delivers native back to the top claim, or `false` if the stack is empty.
  @visibleForTesting
  static Future<bool> handleNativeBack() async {
    if (_stack.isEmpty) return false;
    return _stack.last._onBack();
  }

  /// Clears the stack without calling [ChatPreImeBackNative.release].
  @visibleForTesting
  static void debugReset() => _stack.clear();
}
