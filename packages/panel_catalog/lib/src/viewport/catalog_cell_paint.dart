/// What the painter draws in one cell right now.
///
/// Computed by the binding pool from the leaf's descriptor facts and the asset
/// binding, per paint; never stored on a leaf. One exclusive value, not
/// combinable flags: the painter switches on it.
///
/// Interim: it still projects the legacy readiness flags (hence [failed]) that
/// the asset-cache scope replaces; the replacement derives the same choice
/// from the bound paintable and drops [failed].
enum CatalogCellPaint {
  /// Ready content: a queued sprite, a glyph paragraph, or the ready-path
  /// stand-in for media.
  content,

  /// A baked glyph whose atlas page is not ready yet: a circle in the glyph
  /// box ([kCirclePlaceholderRadiusFactor] of its width). Never selected where
  /// glyphs are drawn as text.
  circle,

  /// Media loading: the thumbnail silhouette.
  thumb,

  /// Sticker loading: the shaped wash.
  wash,

  /// Load failed: a rounded rect stand-in.
  failed,
}
