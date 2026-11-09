import 'dart:ui' show Offset, Radius;

/// The pointer menu's geometry, in logical pixels.
///
/// Every number is the geometry of a desktop popup menu without icons, read
/// from its style and widget definitions, where one style pixel is one logical
/// pixel at interface scale 100%. **verified** names a number read from a
/// source, **derived** one
/// computed from verified numbers, **UNVERIFIED** one no source gives; each
/// unverified value is one constant here and is listed in ADR 026's divergence
/// table.
abstract final class PointerMenuMetrics {
  /// Corner radius of the panel (panel radius; verified).
  static const Radius cornerRadius = Radius.circular(8);

  /// Blur radius of the shadow (shadow blur radius; verified).
  ///
  /// The blur on a rounded rectangle uses a box-ish kernel of this radius,
  /// which is not a Gaussian; a Flutter blur of sigma `radius / 2` is
  /// the closest named mapping. **UNVERIFIED equivalence**: tuned by eye.
  static const double shadowBlur = 5;

  /// Offset of the shadow (shadow offset; verified).
  static const Offset shadowOffset = Offset(0, 1);

  /// Opacity of the shadow colour (shadow colour at 25%;
  /// verified).
  static const double shadowOpacity = 0.25;

  /// Padding above the first row and below the last, filled with the panel
  /// colour (8; verified; the variant with icons
  /// has 5).
  static const double verticalPadding = 8;

  /// Height of a row: `itemPadding` top 8 + the 13 px font's line height 18 +
  /// bottom 7 (**derived**).
  ///
  /// The 18 comes from the bundled font's ascent and descent
  /// (`round(1.0688 * 13 + 0.2930 * 13)`), so it is **UNVERIFIED** against
  /// the platform's real font metrics (a "system font" setting changes it).
  static const double rowHeight = 33;

  /// Distance from the panel's leading edge to the label
  /// (left padding; verified).
  static const double labelStart = 17;

  /// Distance from the label or hint to the panel's trailing edge
  /// (right padding; verified).
  static const double labelEnd = 17;

  /// Gap between the label and a hint or an arrow (right skip;
  /// verified).
  static const double hintGap = 6;

  /// The narrowest a panel is (verified).
  static const double minWidth = 156;

  /// The widest a panel is (verified).
  static const double maxWidth = 300;

  /// Font size of labels and hints (13 px; verified).
  static const double fontSize = 13;

  /// Side of the square the submenu arrow is drawn in (the arrow mask
  /// is 24 x 24; verified).
  static const double arrowBox = 24;

  /// Height of a separator row: 5 above its line, the 1 px line, 5 below
  /// (derived).
  static const double separatorHeight = 11;

  /// Height of the separator's line.
  static const double separatorLine = 1;

  /// How far the panel sits from the pointer along the reading axis: the body's
  /// leading edge is at `pointer.x + 5` (derived from the window margins).
  static const double pointerOffset = 5;

  /// Fraction of its width the panel starts at when it opens
  /// (start width; verified).
  static const double startWidth = 0.5;

  /// Fraction of the show clock over which the width grows
  /// (verified).
  static const double widthDuration = 0.6;

  /// Fraction of its height the panel starts at (verified).
  static const double startHeight = 0.3;

  /// Fraction of the show clock over which the height grows
  /// (verified).
  static const double heightDuration = 0.9;

  /// Fraction of the show clock over which the opacity rises
  /// (uses 0.3; verified). The source also
  /// stores a start opacity of 0.2, which the code multiplies away, so the
  /// effective start is 0.
  static const double opacityDuration = 0.3;

  /// Height of the strip that reveals the content from the top, as a fraction
  /// of the frame (verified).
  static const double fadeHeight = 0.2;

  /// How far the pointer must travel from where the menu opened before rows
  /// react to it (the platform default, 10; **UNVERIFIED**: the
  /// value is not taken from a source).
  static const double mouseGuardDistance = 10;

  /// How many pointer motions before rows react, whatever the distance
  /// (verified).
  static const int mouseGuardMotions = 6;

  /// The largest text scale the panel follows: rows are fixed-height, so the
  /// scale is clamped as the shell's other fixed-height controls are.
  static const double maxTextScale = 1.3;
}
