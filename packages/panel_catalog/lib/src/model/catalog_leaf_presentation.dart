/// How one catalog cell appears while painting.
///
/// Exclusive presentation mode — **not** combinable flags. The viewport
/// projects asset-cache readiness + leaf kind into exactly one value; paint
/// switches on it. Storing a bitmask or multiple simultaneous modes on the
/// leaf would fight the single paint path and duplicate cache readiness.
///
/// | Leaf kind | Loading / unbound | Ready | Failed |
/// |-----------|-------------------|-------|--------|
/// | Unicode, baked (the asset cache has a glyph atlas) | [circlePlaceholder] until its sprite exists | [content] | [failed] |
/// | Unicode, drawn as text (no atlas: the web) | [content] | [content] | [failed] |
/// | Document-backed media | [thumbFirstPlaceholder] | [content] | [failed] |
/// | Sticker | [shapedLoadingWash] | [content] | [failed] |
///
/// Where emoji are baked, a glyph is never drawn as text at scroll time: until
/// its atlas page lands it is the [circlePlaceholder], and it flips to its
/// sprite without a layout change. Where they are not, a glyph is a paragraph
/// with no decode wait, so unbound / loading MUST resolve to [content] and the
/// circle never appears.
///
/// [shapedLoadingWash] is not the loading mode for unicode cells.
enum CatalogLeafPresentation {
  /// Ready glyph or media content (or a ready-path stand-in when decode is
  /// still stubbed for document leaves).
  content,

  /// A baked unicode glyph whose atlas page is not ready yet (glyph
  /// draw-bounds circle).
  ///
  /// Radius is `glyphBounds.width * kCirclePlaceholderRadiusFactor` (~0.4).
  /// MUST NOT be sized against the full cell pitch. Not selected where unicode
  /// is drawn as text — see [CatalogLeafBindingPool.presentationFor].
  circlePlaceholder,

  /// Document-backed loading: static/SVG thumb silhouette (may be stubbed as
  /// a rounded rect until media lands).
  thumbFirstPlaceholder,

  /// Sticker loading wash. MUST NOT be the default for unicode cells.
  shapedLoadingWash,

  /// Load failed; viewport MAY paint a failed stand-in (rounded rect today).
  failed,
}

/// Circle placeholder radius as a fraction of **glyph draw-bounds** width.
///
/// `radius = glyphBounds.width * kCirclePlaceholderRadiusFactor`.
/// MUST NOT be applied against the full cell pitch — that oversizes the
/// circle relative to the eventual glyph.
const double kCirclePlaceholderRadiusFactor = 0.4;

/// Fraction of a cell's shorter side that its glyph is drawn in (the square
/// centred in the cell), whether the glyph is a sprite, a paragraph or the
/// circle placeholder standing in for it.
///
/// Public so a host that bakes glyphs sizes them for the box they will be drawn
/// in instead of copying the number.
const double kCatalogGlyphBoxFraction = 0.72;
