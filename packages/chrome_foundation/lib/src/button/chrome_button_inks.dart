import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';

/// The press and hover colours of chrome buttons, derived from a
/// [ChromePalette]: one source for every button and row that washes on a
/// press or under a mouse.
///
/// A button on the surface ([pressOf], [hoverOf]) washes in the text colour;
/// a button filled with the accent ([pressOnAccentOf], [hoverOnAccentOf])
/// washes in the colour drawn on it.
abstract final class ChromeButtonInks {
  /// The press of a button or a row on the surface: [ChromePalette.onSurface]
  /// at alpha `0x0F`.
  static Color pressOf(ChromePalette palette) =>
      palette.onSurface.withAlpha(0x0F);

  /// The fill under a mouse of a button or a row on the surface:
  /// [ChromePalette.onSurface] at alpha `0x12`.
  static Color hoverOf(ChromePalette palette) =>
      palette.onSurface.withAlpha(0x12);

  /// The press of a button filled with the accent: [ChromePalette.onAccent]
  /// at alpha `0x24`.
  static Color pressOnAccentOf(ChromePalette palette) =>
      palette.onAccent.withAlpha(0x24);

  /// The fill under a mouse of a button filled with the accent:
  /// [ChromePalette.onAccent] at alpha `0x12`.
  static Color hoverOnAccentOf(ChromePalette palette) =>
      palette.onAccent.withAlpha(0x12);
}
