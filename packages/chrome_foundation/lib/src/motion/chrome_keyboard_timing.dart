/// Timing of a soft keyboard that a surface holds down while the
/// keyboard's height stays occupied, and gives back as the surface closes.
abstract final class ChromeKeyboardTiming {
  /// From the start of the surface's close to the keyboard's reopening
  /// (50 ms): the keyboard rises while the surface fades, under the height
  /// still held for it.
  static const Duration heldReopen = Duration(milliseconds: 50);

  /// From the surface's full close to the end of the hold (15 ms): a
  /// keyboard that reopened takes the held height over.
  static const Duration holdRelease = Duration(milliseconds: 15);
}
