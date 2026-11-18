# Changelog

## Unreleased

- Loading stages: `ContentAssetView` forwards every parameter of the core's
  view (`status`, `badge`, `onPlay`, `statusBuilder`, `placeholderUntil`,
  `visibleFraction`, `loadingStyle`, `downloadContext`, `requestsDownload`,
  `underlay`); `loadingRadius` is gone: `status: MediaStatusMode.arc(radius)`.
- `ContentEmbed.stages` (and `ContentEmbedResolver.stages`): an outline
  preview is drawn in the style's fill (a template asset in the text colour)
  and swept by its shimmer; `stages` is a listenable, so an embed follows a
  change of the loading style. `ContentEmbed.binding` exposes the attach,
  over which `mpx_core`'s `ContentStatusOverlay` lays the status control
  and the badge of an embed a body paints on its canvas.
- `ContentAssetScope.withMedia(autoDownload:)` and `autoDownload`;
  `attach`, `ContentEmbed` and `ContentEmbedResolver` take a
  `downloadContext`. A glyph binding has no transfer and nothing to
  download.
- `ContentDescriptorMedia.mediaDescriptor` maps the byte size, duration,
  streaming flag and preview (the byte size and duration were dropped).
- `ContentAssetPresets.roundVideo`: a round, filled, playing clip.
- `ContentEmbed` composites a texture through `mpx_core`'s
  `AssetTextureLayer`; the package's own copy is gone.
- A glyph binding answers `visibleFraction` (a still: it only reads back).

## 0.1.0

- What stayed in the chat when `catalog_assets` moved to `mpx_core`: inline
  embeds and the chat presets (now `ContentAssetPresets`), over the core's
  asset cache.
- `ContentAssetScope`: attaches content by `ContentKey`, media to the core's
  scope under its `MediaKey`, glyphs to the glyph atlas. Glyphs no longer go
  through the cache or a producer: without a source they are drawn as text
  by their binding (`TextGlyphProducer` is gone).
- `ContentAssetView` and `ContentAssetProvider` in place of the cache's
  `ContentView` and `AssetCacheProvider` for content keyed by `ContentKey`.
- `ContentKeyMedia`, `ContentDescriptorMedia`, `ContentMediaResolver`: the
  mapping to the core's identity and resolver seam.
