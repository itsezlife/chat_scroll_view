import 'dart:ui' show Offset, Radius;

/// The pointer menu's geometry, in logical pixels.
///
/// Every number is the reference desktop client's popup (`Ui::PopupMenu` with
/// the plain `defaultPopupMenu` style: no icons), read from its `.style` files
/// and widget code, where a `.style` pixel is one logical pixel at interface
/// scale 100%. **verified** names a number read from a file, **derived** one
/// computed from verified numbers, **UNVERIFIED** one no source gives; each
/// unverified value is one constant here and is listed in ADR 026's divergence
/// table.
abstract final class PointerMenuMetrics {
  /// Corner radius of the panel (`defaultPopupMenu.radius`; verified).
  static const Radius cornerRadius = Radius.circular(8);

  /// Blur radius of the shadow (`defaultBoxShadow.blurRadius`; verified).
  ///
  /// The reference blurs a rounded rectangle with a box-ish kernel of this
  /// radius, which is not a Gaussian; a Flutter blur of sigma `radius / 2` is
  /// the closest named mapping. **UNVERIFIED equivalence**: tuned by eye.
  static const double shadowBlur = 5;

  /// Offset of the shadow (`defaultBoxShadow.offset`; verified).
  static const Offset shadowOffset = Offset(0, 1);

  /// Opacity of the shadow colour (`defaultBoxShadow` colour at 25%;
  /// verified).
  static const double shadowOpacity = 0.25;

  /// Padding above the first row and below the last, filled with the panel
  /// colour (`defaultPopupMenu.scrollPadding`, 8; verified; the icon variant
  /// has 5).
  static const double verticalPadding = 8;

  /// Height of a row: `itemPadding` top 8 + the 13 px font's line height 18 +
  /// bottom 7 (**derived**).
  ///
  /// The 18 comes from the bundled Open Sans file's ascent and descent
  /// (`round(1.0688 * 13 + 0.2930 * 13)`), so it is **UNVERIFIED** against
  /// the real `QFontMetricsF` (a "system font" setting changes it).
  static const double rowHeight = 33;

  /// Distance from the panel's leading edge to the label
  /// (`itemPadding.left`; verified).
  static const double labelStart = 17;

  /// Distance from the label or hint to the panel's trailing edge
  /// (`itemPadding.right`; verified).
  static const double labelEnd = 17;

  /// Gap between the label and a hint or an arrow (`itemRightSkip`;
  /// verified).
  static const double hintGap = 6;

  /// The narrowest a panel is (`defaultMenu.widthMin`; verified).
  static const double minWidth = 156;

  /// The widest a panel is (`defaultMenu.widthMax`; verified).
  static const double maxWidth = 300;

  /// Font size of labels and hints (`defaultTextStyle` 13 px; verified).
  static const double fontSize = 13;

  /// Side of the square the submenu arrow is drawn in (`menu/submenu_arrow`
  /// is 24 x 24; verified).
  static const double arrowBox = 24;

  /// Height of a separator row: 5 above its line, the 1 px line, 5 below
  /// (`defaultMenuSeparator`; derived).
  static const double separatorHeight = 11;

  /// Height of the separator's line.
  static const double separatorLine = 1;

  /// How far the panel sits from the pointer along the reading axis: the body's
  /// leading edge is at `pointer.x + 5` (derived from the window margins in
  /// `PopupMenu::prepareGeometryFor`).
  static const double pointerOffset = 5;

  /// Fraction of its width the panel starts at when it opens
  /// (`PanelAnimation.startWidth`; verified).
  static const double startWidth = 0.5;

  /// Fraction of the show clock over which the width grows
  /// (`widthDuration`; verified).
  static const double widthDuration = 0.6;

  /// Fraction of its height the panel starts at (`startHeight`; verified).
  static const double startHeight = 0.3;

  /// Fraction of the show clock over which the height grows
  /// (`heightDuration`; verified).
  static const double heightDuration = 0.9;

  /// Fraction of the show clock over which the opacity rises
  /// (`PanelAnimation::computeState` uses 0.3; verified). The style also
  /// stores `startOpacity` 0.2, which the code multiplies away, so the
  /// effective start is 0.
  static const double opacityDuration = 0.3;

  /// Height of the strip that reveals the content from the top, as a fraction
  /// of the frame (`fadeHeight`; verified).
  static const double fadeHeight = 0.2;

  /// How far the pointer must travel from where the menu opened before rows
  /// react to it (Qt's default `startDragDistance`, 10; **UNVERIFIED**: the
  /// value is the platform's, not in the checkout).
  static const double mouseGuardDistance = 10;

  /// How many pointer motions before rows react, whatever the distance
  /// (`Menu::hasMouseMoved`; verified).
  static const int mouseGuardMotions = 6;

  /// The largest text scale the panel follows: rows are fixed-height, so the
  /// scale is clamped as the shell's other fixed-height controls are.
  static const double maxTextScale = 1.3;
}
