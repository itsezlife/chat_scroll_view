import 'dart:math' as math;

/// Fraction of a cell's shorter side that its glyph is drawn in (the square
/// centred in the cell), whether the glyph is a sprite, a paragraph or the
/// circle placeholder standing in for it.
///
/// Public so a host that bakes glyphs sizes them for the box they will be drawn
/// in instead of copying the number. [catalogGlyphBoxExtent] is the one formula
/// that applies it.
const double kCatalogGlyphBoxFraction = 0.72;

/// Circle placeholder radius as a fraction of the **glyph box** width.
///
/// `radius = glyphBoxExtent * kCirclePlaceholderRadiusFactor`. It MUST NOT be
/// applied against the full cell pitch: that oversizes the circle relative to
/// the glyph that replaces it.
const double kCirclePlaceholderRadiusFactor = 0.4;

/// The side of the glyph box drawn in a cell of [cellWidth] x [cellHeight]:
/// [kCatalogGlyphBoxFraction] of the shorter side, or [fixed] (a grid's
/// `glyphExtent`) held to the shorter side.
///
/// The painter draws every glyph, sprite or placeholder in this box, and
/// [largestCatalogGlyphBox] takes the maximum of it over the cells a catalog
/// can show, so the two cannot disagree about how large a glyph is.
double catalogGlyphBoxExtent(
  double cellWidth,
  double cellHeight, {
  double? fixed,
}) {
  final side = math.min(cellWidth, cellHeight);
  return switch (fixed) {
    final extent? => math.min(extent, side),
    null => side * kCatalogGlyphBoxFraction,
  };
}

/// The square a leaf's content is asked for from the cache and drawn in,
/// centred in its cell.
enum CatalogContentBox {
  /// [kCatalogGlyphBoxFraction] of the cell's shorter side: an emoji, which
  /// sits in the text-like box and leaves room around it.
  glyph,

  /// The cell's shorter side: a sticker or a GIF, which fills its cell.
  cell,
}

/// The side of the square [box] draws content in, in a cell of [cellWidth] x
/// [cellHeight], with the grid's fixed [glyphExtent] if it has one. Both the
/// cache request and the paint read it, so the pixels asked for are the pixels
/// drawn.
double catalogContentBoxExtent(
  CatalogContentBox box,
  double cellWidth,
  double cellHeight, {
  double? glyphExtent,
}) => switch (box) {
  CatalogContentBox.glyph => catalogGlyphBoxExtent(
    cellWidth,
    cellHeight,
    fixed: glyphExtent,
  ),
  CatalogContentBox.cell => math.min(cellWidth, cellHeight),
};
