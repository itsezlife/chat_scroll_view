# Changelog

All notable changes to `chat_chrome` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- **Baked emoji atlas.** The panel shell owns an `EmojiGlyphAtlasHost`: the emoji
  grid draws sprites cut from baked pages. The host outlives the grid page, so
  closing and reopening the panel does not bake again; the pages stay resident
  while the panel is open and for a retention after it closes, and a
  persistence given to the host keeps them across launches.

### Removed

- **Glass exports** (`LiquidGlass`, `LiquidGlassStyle`, `GlassBackdrop`,
  `GlassSource`, `GlassSourceScope`, `LiquidGlassShader`, the glass shaders).
  The glass stack moved to `chrome_foundation` as `GlassSurface` with named
  `GlassMaterial`s, a `GlassQualityScope` policy and `GlassSourceScope` /
  `GlassSource`. The composer island draws through `GlassSurface`; a host that
  used the old widgets imports `package:chrome_foundation`.
- **`ScalePressable` and `OvershootCurve` exports.** Both moved to
  `chrome_foundation`; the package now depends on it for them. A host that
  imported either through `chat_chrome` imports `package:chrome_foundation`.
- **`EmojiPageState.warmAhead`.** The cold-start warm-up it forwarded to is gone
  from `panel_catalog` (the atlas bakes in the background). A host that called
  it drops the call; nothing replaces it.
