/// Counters a host or a test reads to learn *how* the viewport drew, never
/// whether it drew correctly.
///
/// Kept apart from `panel_catalog_perf_probe.dart`, which is temporary: this
/// outlives the investigation because the rule it checks outlives it.
library;

/// How the viewport has drawn glyphs since the last [reset].
///
/// On a platform that bakes emoji the viewport draws every glyph as a sprite
/// cut from an atlas page and never as text, so [glyphParagraphDraws] stays `0`
/// however much is scrolled. The count is bumped only on the paragraph path,
/// so the sprite path pays nothing for it and a release build keeps the
/// counter at no cost to the hot path it guards.
abstract final class PanelCatalogDiagnostics {
  /// Glyph paragraphs drawn as text (the web strategy, or a surface whose
  /// cache has no atlas). `0` where emoji are baked.
  static int glyphParagraphDraws = 0;

  /// Sets every counter back to zero.
  static void reset() {
    glyphParagraphDraws = 0;
  }
}
