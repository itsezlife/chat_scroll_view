/// Geometry of the composer island, in logical pixels.
///
/// These are component constants, not theme tokens: they are tuned together
/// and a host that wants other values replaces the view, not a number. Paint
/// sizes are listed, not outer hit boxes, unless stated.
///
/// **Radius and height.** [islandRadius] is half of [islandHeight], so the
/// idle island is a full stadium. A taller island with the same radius reads
/// less round; keep the single-line height at [islandHeight].
abstract final class ComposerMetrics {
  /// Height of the island with one line of text and no header.
  static const double islandHeight = 44;

  /// Corner radius of the island glass.
  static const double islandRadius = 22;

  /// Gap between the island's side and the view's edge.
  static const double islandSideGap = 7;

  /// Gap above the island, inside the view.
  static const double islandTopGap = 10;

  /// Gap between the island's bottom and the view's bottom edge, before any
  /// safe-area pad.
  static const double islandBottomGap = 9;

  /// Widest the island grows; it centres when the view is wider.
  static const double maxWidth = 620;

  /// Height of the header strip when fully revealed.
  static const double headerHeight = 48;

  /// Side of the square hit target of an action (the paint is smaller).
  static const double actionSize = 44;

  /// Size of an action's glyph.
  static const double actionIconSize = 24;

  /// Diameter of the filled disc behind a primary action's glyph.
  static const double primaryDiscDiameter = 32;

  /// Most lines the field grows to before it scrolls.
  static const int fieldMaxLines = 6;

  /// Font size of the field's text, before the text scale.
  static const double fieldFontSize = 18;

  /// Line height of the field's text, as a multiple of the font size.
  static const double fieldLineHeight = 1.25;

  /// Padding above the field's text inside the row.
  static const double fieldTopPad = 9;

  /// Padding below the field's text inside the row.
  static const double fieldBottomPad = 10;

  /// Padding between the field and the trailing edge of its slot.
  static const double fieldEndPad = 4;

  /// Smallest change of a measured height that starts a new height
  /// animation.
  static const double heightEpsilon = 0.5;
}
