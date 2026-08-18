import 'package:flutter/services.dart';

const _channel = MethodChannel('chat_scroll_view_example/selection_cap_haptic');

/// Telegram selection-limit haptic.
///
/// iOS: `UINotificationFeedbackGenerator` `.error` — Flutter's
/// [HapticFeedback] has no error/notification impact.
/// Android: `ChatActivity.addToSelectedMessages` at cap —
/// `vibrator.vibrate(200)` (200 ms one-shot, not `APP_ERROR`).
///
/// Falls back to [HapticFeedback.heavyImpact] when the platform channel
/// is missing (widget tests, desktop).
Future<void> playSelectionCapHaptic() async {
  try {
    await _channel.invokeMethod<void>('playError');
  } on MissingPluginException {
    await HapticFeedback.heavyImpact();
  }
}
