/// How one catalog cell appears while painting.
///
/// Exclusive presentation mode — **not** combinable flags. The viewport
/// projects asset-cache readiness + leaf kind into exactly one value; paint
/// switches on it. Storing a bitmask or multiple simultaneous modes on the
/// leaf would fight the single paint path and duplicate cache readiness.
///
/// | Leaf kind | Loading / unbound | Ready | Failed |
/// |-----------|-------------------|-------|--------|
/// | Unicode (paragraph paint) | [content] | [content] | [failed] |
/// | Document-backed media | [thumbFirstPlaceholder] | [content] | [failed] |
/// | Sticker | [shapedLoadingWash] | [content] | [failed] |
///
/// [circlePlaceholder] remains for a future bitmap-page unicode path (async
/// page decode). The current unicode leaf paints glyphs via paragraph cache
/// with no decode wait — unbound/loading MUST resolve to [content] so pager
/// keep-alive gaps do not flash empty circles.
///
/// [shapedLoadingWash] is not the loading mode for unicode cells.
enum CatalogLeafPresentation {
  /// Ready glyph or media content (or a ready-path stand-in when decode is
  /// still stubbed for document leaves).
  content,

  /// Reserved for async bitmap-page unicode loading (glyph draw-bounds circle).
  ///
  /// Radius is `glyphBounds.width * kCirclePlaceholderRadiusFactor` (~0.4).
  /// MUST NOT be sized against the full cell pitch. Current
  /// [UnicodeCatalogLeaf] paragraph paint does not select this mode for
  /// unbound/loading — see [CatalogLeafBindingPool.presentationFor].
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
