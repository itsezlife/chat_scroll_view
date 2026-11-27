/// Timing of a hint shown at a control, such as the one a tap on a denied
/// action brings up.
abstract final class ChromeHintTiming {
  /// How long a hint at a control stays up (2.3 s). A control that reports
  /// a tap for such a hint ignores a repeat within it, so a burst of taps
  /// does not stack hints.
  static const Duration controlHint = Duration(milliseconds: 2300);

  /// How long a hint at a tab of a page that is not available stays up
  /// (3.5 s): a tab names a whole page, and its hint is read in full before
  /// the user tries again. A repeat tap within it is ignored, as at a
  /// control.
  static const Duration tabHint = Duration(milliseconds: 3500);
}
