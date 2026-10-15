/// Counters a host or a test reads to learn *how* the viewport drew, never
/// whether it drew correctly.
///
/// Observation only: nothing in the engine reads these values, so they never
/// change what is drawn. They stay in release and profile builds (unlike an
/// assert-only counter) because the rule they check, that emoji are not drawn
/// as text where they are baked, is verified on a profile build on a device.
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

  /// Most glyph paragraphs one viewport keeps cached on the paragraph path.
  ///
  /// A paragraph is keyed by glyph and layout width, so a window that is
  /// resized step by step makes every visible glyph a new key per step. The
  /// least recently drawn paragraph is dropped past this count. It is far above
  /// what one screen draws, so scrolling and a settled layout never evict.
  static const int glyphParagraphCacheLimit = 1024;

  /// Glyph paragraphs held right now by all live viewports (a gauge, not a
  /// count of events: [reset] leaves it alone, a viewport gives its share back
  /// when it is disposed).
  static int glyphParagraphsCached = 0;

  /// Sets every counter back to zero.
  static void reset() {
    glyphParagraphDraws = 0;
  }
}
