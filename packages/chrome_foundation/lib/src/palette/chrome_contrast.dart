import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.x contrast arithmetic for chrome colours.
///
/// Chrome tokens are often translucent (a hint is the text colour at some
/// alpha), so every measurement first composites the colours over what they
/// are drawn on. The thresholds are the callers' choice; the ones the palette
/// tests use are [minimumText] and [minimumIcon].
abstract final class ChromeContrast {
  /// Level AA for normal-size text (WCAG 1.4.3).
  static const double minimumText = 4.5;

  /// Level AA for icons and other graphical objects (WCAG 1.4.11).
  static const double minimumIcon = 3;

  /// Contrast ratio between [foreground] and [background], in `[1, 21]`.
  ///
  /// The order of the arguments does not change the result. Translucent
  /// colours are composited first: [background] over [backdrop], then
  /// [foreground] over that. [backdrop] defaults to opaque white; it only
  /// matters when [background] is translucent.
  static double ratio(
    Color foreground,
    Color background, {
    Color backdrop = const Color(0xFFFFFFFF),
  }) {
    final surface = Color.alphaBlend(background, backdrop);
    final ink = Color.alphaBlend(foreground, surface);
    final a = ink.computeLuminance();
    final b = surface.computeLuminance();
    return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
  }
}
