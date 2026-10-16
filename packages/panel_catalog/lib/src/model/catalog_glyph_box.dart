import 'dart:math' as math;

/// The square a leaf's content is asked for from the cache and drawn in,
/// centred in its cell.
enum CatalogContentBox {
  /// [glyphBoxFraction] of the cell's shorter side: an emoji, which sits in
  /// the text-like box and leaves room around it.
  glyph,

  /// The cell's shorter side: a sticker or a GIF, which fills its cell.
  cell;

  /// Fraction of a cell's shorter side that its glyph is drawn in (the square
  /// centred in the cell), whether the glyph is a sprite, a paragraph or the
  /// circle placeholder standing in for it.
  ///
  /// Public so a host that bakes glyphs sizes them for the box they will be
  /// drawn in instead of copying the number. [glyphBoxExtent] is the one
  /// formula that applies it.
  static const double glyphBoxFraction = 0.72;

  /// The side of the glyph box drawn in a cell of [cellWidth] x [cellHeight]:
  /// [glyphBoxFraction] of the shorter side, or [fixed] (a grid's
  /// `glyphExtent`) held to the shorter side.
  ///
  /// The painter draws every glyph, sprite or placeholder in this box, and
  /// `PanelCatalogViewport.largestGlyphBox` takes the maximum of it over the
  /// cells a catalog can show, so the two cannot disagree about how large a
  /// glyph is.
  static double glyphBoxExtent(
    double cellWidth,
    double cellHeight, {
    double? fixed,
  }) {
    final side = math.min(cellWidth, cellHeight);
    return switch (fixed) {
      final extent? => math.min(extent, side),
      null => side * glyphBoxFraction,
    };
  }

  /// The side of the square this box draws content in, in a cell of
  /// [cellWidth] x [cellHeight], with the grid's fixed [glyphExtent] if it has
  /// one. Both the cache request and the paint read it, so the pixels asked
  /// for are the pixels drawn.
  double extentIn(double cellWidth, double cellHeight, {double? glyphExtent}) =>
      switch (this) {
        CatalogContentBox.glyph => glyphBoxExtent(
          cellWidth,
          cellHeight,
          fixed: glyphExtent,
        ),
        CatalogContentBox.cell => math.min(cellWidth, cellHeight),
      };
}
