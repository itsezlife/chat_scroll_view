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
/// however much is scrolled. The count is bumped only for a glyph whose
/// paintable draws itself (the strategy that draws text), so the sprite path
/// pays nothing for it and a release build keeps the counter at no cost to the
/// hot path it guards.
abstract final class PanelCatalogDiagnostics {
  /// Unicode glyphs drawn as text by their own paintable (the strategy of a
  /// platform that bakes nothing). `0` where emoji are baked.
  static int glyphParagraphDraws = 0;

  /// Sets every counter back to zero.
  static void reset() {
    glyphParagraphDraws = 0;
  }
}
