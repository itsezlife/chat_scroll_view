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
/// [kCatalogGlyphBoxFraction] of the shorter side.
///
/// The painter draws every glyph, sprite or placeholder in this box, and
/// [largestCatalogGlyphBox] takes the maximum of it over the cells a catalog
/// can show, so the two cannot disagree about how large a glyph is.
double catalogGlyphBoxExtent(double cellWidth, double cellHeight) =>
    math.min(cellWidth, cellHeight) * kCatalogGlyphBoxFraction;
