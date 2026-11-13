# Changelog

## 0.1.0

- The glyph atlas of `catalog_assets` as a package of its own over
  `mpx_core`: baking, paging, residency, the disk cache, and the glyph
  sources (`GlyphSpriteSource`, `LayeredGlyphSource`). Sprites are
  `mpx_core`'s `AtlasSprite`.
- `ParagraphGlyphRasteriser.defaultFontScale` (0.85): the glyph's font size
  as a fraction of its box, for any surface that draws an emoji beside baked
  ones.
