/// Timing of the input guard on a control whose action opens or removes
/// something, so a burst of taps acts once.
abstract final class ChromeTapTiming {
  /// How long after an accepted tap such a control ignores the next one
  /// (400 ms): a double tap on a dismiss control dismisses once, instead of
  /// landing its second tap on what appears in its place, and one on an
  /// open action opens once.
  static const Duration repeatGuard = Duration(milliseconds: 400);
}
