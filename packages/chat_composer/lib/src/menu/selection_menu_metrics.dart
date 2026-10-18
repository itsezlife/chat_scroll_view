/// The selection menu's geometry, in logical pixels.
///
/// One set of constants: nothing differs between platforms, and the colours
/// and durations are tokens and motion roles (ADR 027).
abstract final class SelectionMenuMetrics {
  /// Height of a row of the main page and of a tile of the More page.
  static const double tileHeight = 42;

  /// Horizontal padding inside a main-row button.
  static const double buttonPadding = 12;

  /// Horizontal padding inside a More-page tile.
  static const double tilePadding = 18;

  /// Size of the More and Back icons.
  static const double iconSize = 24;

  /// Space between a tile's leading icon and its label.
  static const double leadingGap = 12;

  /// Width of the leading column of a list tile, so a bullet and a number
  /// keep their labels aligned.
  static const double listMarkerWidth = 16;

  /// Space between a list marker and its label.
  static const double listMarkerGap = 8;

  /// Space the More button keeps from the card's end.
  static const double moreButtonEndPadding = 4;

  /// Width the More button takes on the main row.
  static const double moreButtonWidth = tileHeight + moreButtonEndPadding;

  /// Thickness of the line between the More page's list and its Back tile.
  static const double dividerThickness = 1;

  /// The Back tile and the room a page keeps for it when it limits its list:
  /// the tile and a tile-sized gap's worth of margin, as the card's height
  /// budget counts them.
  static const double pageHeaderBudget = 50;

  /// Width of the More page.
  static const double pageWidth = 150;

  /// Widest the main row may be.
  static const double rowMaxWidth = 400;

  /// Tallest the menu asks to be; it takes less where the room is short.
  static const double maxHeight = 320;

  /// Room kept between the menu and the edges of the screen, the safe area
  /// and the keyboard.
  static const double regionMargin = 12;

  /// Space between the card and the selection when it sits above it.
  static const double gapAbove = 8;

  /// Space between the card and the selection when it sits below it: the
  /// platform toolbar's content distance, which leaves room for a handle.
  static const double gapBelow = 20;

  /// Room under which a side is "cramped": the menu goes to the other side if
  /// that has more.
  static const double minUsableHeight = 96;

  /// How far the card drifts, in the direction away from the selection, while
  /// it leaves.
  static const double leaveDrift = 5;

  /// The text scale the menu follows. Its rows are fixed-height, so past this
  /// the glyphs would clip; a deliberate deviation from an unclamped scale.
  static const double maxTextScale = 1.3;

  /// Font size of every label.
  static const double labelFontSize = 16;

  /// The swipe speed, in logical pixels per second, from which a drag across
  /// the More page closes it whatever its position.
  static const double flingVelocity = 600;
}
