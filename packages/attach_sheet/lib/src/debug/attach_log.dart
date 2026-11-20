import 'package:flutter/foundation.dart';

/// The attach sheet's diagnostic log: one line per event, prefixed with its
/// area in brackets (`[attach.caption]`, `[attach.panel]`, `[attach.ime]`,
/// `[attach.focus]`, `[attach.chat]`),
/// so a device log filters on the prefix.
///
/// On in debug and profile builds while [enabled]; nothing in release.
abstract final class AttachLog {
  /// Whether lines are written; a host or a test turns it off.
  static bool enabled = !kReleaseMode;

  /// The caption field: focus, text, inline content.
  static const String caption = 'attach.caption';

  /// The caption's panel: requests, shows, hides, its slot and tickers.
  static const String panel = 'attach.panel';

  /// The soft keyboard: insets and the height remembered for the panel.
  static const String ime = 'attach.ime';

  /// Focus: every primary focus change while the sheet is up.
  static const String focus = 'attach.focus';

  /// The host's side: the chat's snapshot at open, its decisions at close,
  /// its keyboard requests.
  static const String chat = 'attach.chat';

  /// Writes [message] under [area].
  static void log(String area, String message) {
    if (kReleaseMode || !enabled) return;
    debugPrint('[$area] $message');
  }
}
