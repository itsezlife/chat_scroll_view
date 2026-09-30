# Panel catalog leaf placeholders

Each catalog leaf kind has its own loading paint. Pick the matching one
before reaching for a generic “shimmer”.

## Three different loading paints (do not conflate)

| Catalog kind | Loading paint | What you see while loading |
| ------------ | ------------- | -------------------------- |
| Standard emoji bitmap pages | Circle placeholder | **Solid circle**, not a moving shimmer |
| Animated / custom emoji | Static thumb (often SVG) | **Thumb-first** silhouette, then media |
| Stickers (shaped wash) | SVG mask × moving gradient | SVG path × **moving** gradient (true shimmer-on-shape) |

Calling every placeholder “shimmer” is wrong for keyboard emoji.

## Standard emoji — circle placeholder

While the glyph's bitmap page is not loaded, request the page and paint a
filled circle centered in the glyph bounds instead of the glyph.

| Role | Value |
| ---- | ----- |
| Shape | Circle |
| Radius | `0.4 × bounds.width` (glyph draw bounds, not full cell pitch) |
| Fill | `placeholderColor` default `0x10000000`; inline text tints via `0x10ffffff & textColor` |
| Motion | None — static until bitmap page loads |

Animated leaves never use this circle, even though a translucent placeholder
tint (`0x0fffffff` / `0x0f000000`) exists for theme updates.

## Animated emoji — thumb-first, not circle

Keyboard-grid animated emoji share one drawable map per grid. While document
media is not ready, the cell paints the document's static thumb (often an
SVG thumb at alpha ≈ 0.2). That is the loading stand-in — **shape of the
sticker/emoji thumb**, not the circle.

## Stickers — shaped loading wash

SVG alpha mask × horizontal linear gradient translated over ~1800ms. Use this
pattern for **sticker** leaves, not as the default for unicode emoji cells.

## Flutter mapping (Panel Catalog)

| Role | Flutter |
| ---- | ------- |
| Circle placeholder fill | [PanelCatalogThemeData.placeholderColor] (default `0x10000000` light) |
| Press list-selector | [PanelCatalogThemeData.leafPressHighlightColor] on full cell rect |
| Press selector corner | [PanelCatalogThemeData.selectorRadiusLogicalPx] (`nominalDp × DPR`) |
| Section header title | [PanelCatalogThemeData.sectionHeaderStyle] |
| RRect stand-in corner | [PanelCatalogThemeData.standInCornerRadius] (default `6`) |
| Document ready-path stub | [PanelCatalogThemeData.documentStandInColor] |

| Leaf kind | Leaf presentation while loading |
| --------- | -------------------------------- |
| Unicode / bitmap glyph | Circle placeholder |
| Document-backed animated | Thumb-first (SVG/static), then drawable |
| Sticker | Shaped loading wash |

Viewport paints the matching placeholder mode; catalog data source owns fetch
and readiness notify. Hosts scope tokens with [PanelCatalogTheme].
