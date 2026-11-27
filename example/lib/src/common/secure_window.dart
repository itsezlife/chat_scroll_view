import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('chat_scroll_view_example/system');

/// Turns the platform's secure flag of the app's window on or off: screen
/// captures and recordings show the window blank while it is on.
///
/// Android sets `FLAG_SECURE` on the activity's window; macOS sets the
/// window's sharing type to none. Every other platform has no flag the app
/// sets (iOS offers none, Windows' display affinity is not wired, the web
/// cannot), and nothing happens there.
///
/// Returns whether the flag was applied on this platform: false where there
/// is none, or when the platform channel is missing (widget tests).
Future<bool> setSecureWindow({required bool secure}) async {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android || TargetPlatform.macOS:
      try {
        await _channel.invokeMethod<void>('secureWindow', secure);
        return true;
      } on MissingPluginException {
        return false;
      }
    case TargetPlatform.iOS ||
        TargetPlatform.fuchsia ||
        TargetPlatform.windows ||
        TargetPlatform.linux:
      return false;
  }
}
