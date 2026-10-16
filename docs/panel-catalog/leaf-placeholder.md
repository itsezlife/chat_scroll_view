# Panel catalog leaf placeholders

Each catalog leaf kind has its own loading paint. Pick the matching one
before reaching for a generic “shimmer”.

## Three different loading paints (do not conflate)

| Catalog kind | Loading paint | What you see while loading |
| ------------ | ------------- | -------------------------- |
| Unicode emoji (baked glyph) | Circle placeholder | **Solid circle** until the glyph is baked, not a moving shimmer |
| Animated / custom emoji | Static thumb (often SVG) | **Thumb-first** silhouette, then media |
| Stickers (shaped wash) | SVG mask × moving gradient | SVG path × **moving** gradient (true shimmer-on-shape) |

Calling every placeholder “shimmer” is wrong for keyboard emoji.

## Unicode emoji — circle placeholder

While the glyph is not baked into an atlas page yet, paint a filled circle
centered in the glyph bounds instead of the sprite. There is no time limit:
the circle stays until the sprite exists. With a valid disk cache it lasts at
most 500 ms after a cold start. A strategy that draws paragraphs (web) has no
unbaked state and never paints it.

| Role | Value |
| ---- | ----- |
| Shape | Circle |
| Radius | `0.4 × bounds.width` (glyph draw bounds, not full cell pitch) |
| Fill | `placeholderColor` default `0x10000000`; inline text tints via `0x10ffffff & textColor` |
| Motion | None — static until the glyph is baked |

The cell flips from the circle to the sprite when its atlas page is ready,
with no layout change. The circle returns, or stays, when:

| Situation | What the cell shows |
| --------- | ------------------- |
| First run, nothing persisted | Circle until the glyph's page is baked (the visible page bakes first) |
| Cold start, valid disk cache | Circle until the page is restored, at most 500 ms |
| Glyph the atlas did not plan (for example a skin tone chosen for the first time) | Circle until the next bake covers it; the art already drawn keeps drawing |
| System emoji art or catalogue changed (stale) | The old sprite, then every cell changes at once when the new set is complete |
| Screen density or baked cell size differs from the persisted pages (discard) | Circle, as on a first run; when the density changes in a running session the art already drawn stays until the new set is complete |
| A page released on memory pressure | Its cells draw again once the page is read back from the page store |

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

| Leaf kind | Placeholder while loading (`CatalogLeaf.placeholderStyle`, derived from the leaf's descriptor facts) |
| --------- | -------------------------------- |
| Unicode glyph, baking platform | Circle placeholder until baked, then sprite |
| Unicode glyph, paragraph strategy (web) | The glyph, drawn as text; no placeholder |
| Document-backed animated | Thumb-first (SVG/static), then drawable |
| Sticker | Shaped loading wash |

A leaf marked failed paints the rounded stand-in rectangle of the other kinds.
Viewport paints the matching placeholder mode; catalog data source owns fetch
and readiness notify. Hosts scope tokens with [PanelCatalogTheme].
