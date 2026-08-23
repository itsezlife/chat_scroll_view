import 'dart:developer' as dev;

/// Temporary debug logger for emoji / keyboard-slot wiring.
///
/// Filter logcat / console with: `chat_chrome`
void chatChromeLog(String message) {
  dev.log(message, name: 'chat_chrome');
}
