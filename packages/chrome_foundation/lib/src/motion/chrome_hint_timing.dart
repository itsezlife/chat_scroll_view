/// Timing of a hint shown at a control, such as the one a tap on a denied
/// action brings up.
abstract final class ChromeHintTiming {
  /// How long a hint at a control stays up (2.3 s). A control that reports
  /// a tap for such a hint ignores a repeat within it, so a burst of taps
  /// does not stack hints.
  static const Duration controlHint = Duration(milliseconds: 2300);
}
