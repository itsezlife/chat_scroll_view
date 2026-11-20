import 'package:flutter/foundation.dart';

/// The attach sheet's diagnostic log: one line per event, prefixed with its
/// area in brackets (`[attach.caption]`, `[attach.panel]`, `[attach.ime]`),
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

  /// Writes [message] under [area].
  static void log(String area, String message) {
    if (kReleaseMode || !enabled) return;
    debugPrint('[$area] $message');
  }
}
