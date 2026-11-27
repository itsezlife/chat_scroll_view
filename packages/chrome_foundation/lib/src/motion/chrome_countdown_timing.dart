/// How often a countdown shown in chrome (slow mode's wait before the next
/// send) redraws, by where it is drawn.
///
/// A countdown shows whole seconds, so any period up to a second keeps it
/// right; a shorter one turns the second over closer to the moment it
/// passes, at the cost of more frames.
abstract final class ChromeCountdownTiming {
  /// A countdown in place of a control's glyph that redraws every tenth of
  /// a second (100 ms).
  static const Duration control = Duration(milliseconds: 100);

  /// A countdown in a control that polls its wait five times a second
  /// (200 ms).
  static const Duration polledControl = Duration(milliseconds: 200);

  /// A countdown in a field's placeholder, redrawn twice a second (500 ms).
  static const Duration placeholder = Duration(milliseconds: 500);
}
