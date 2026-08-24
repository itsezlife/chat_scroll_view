/// How one catalog cell appears while painting.
///
/// Exclusive presentation mode — **not** combinable flags. The viewport
/// projects asset-cache readiness + leaf kind into exactly one value; paint
/// switches on it. Storing a bitmask or multiple simultaneous modes on the
/// leaf would fight the single paint path and duplicate cache readiness.
///
/// | Leaf kind | Loading | Ready | Failed |
/// |-----------|---------|-------|--------|
/// | Unicode / bitmap glyph | [circlePlaceholder] | [content] | [failed] |
/// | Document-backed media | [thumbFirstPlaceholder] | [content] | [failed] |
/// | Sticker | [shapedLoadingWash] | [content] | [failed] |
///
/// [shapedLoadingWash] is not the loading mode for unicode cells — circle
/// geometry is.
enum CatalogLeafPresentation {
  /// Ready glyph or media content (or a ready-path stand-in when decode is
  /// still stubbed for document leaves).
  content,

  /// Unicode loading: solid circle centered in glyph draw bounds.
  ///
  /// Radius is `glyphBounds.width * kCirclePlaceholderRadiusFactor`
  /// (~0.4). MUST NOT be sized against the full cell pitch — glyph bounds are
  /// a centered fraction of the cell (~72% pitch).
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
