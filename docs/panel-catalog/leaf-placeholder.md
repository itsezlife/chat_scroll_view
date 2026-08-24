# Panel catalog leaf placeholders — Telegram TRACE

Apply [extracting-metrics.md](../../.cursor/skills/telegram-java-to-flutter/extracting-metrics.md)
before inventing a generic “shimmer”.

Sources: `Emoji.SimpleEmojiDrawable`, `AnimatedEmojiDrawable` + `ImageReceiver`,
`LoadingStickerDrawable`, `EmojiView` keyboard grid (`CACHE_TYPE_KEYBOARD`).

## Three different loading paints (do not conflate)

| Catalog kind | Java | What you see while loading |
| ------------ | ---- | -------------------------- |
| Standard emoji bitmap pages | `Emoji.SimpleEmojiDrawable.draw` | **Solid circle**, not a moving shimmer |
| Animated / custom emoji | `AnimatedEmojiDrawable` → `ImageReceiver` + `staticThumb` (often SVG thumb) | **Thumb-first** silhouette, then media |
| Stickers (shaped wash) | `LoadingStickerDrawable` | SVG path × **moving** gradient (true shimmer-on-shape) |

Calling every placeholder “shimmer” is wrong for keyboard emoji parity.

## Standard emoji — circle placeholder (TRACE)

```java
// Emoji.SimpleEmojiDrawable.draw
if (!isLoaded()) {
    loadEmoji(info.page, info.page2);
    placeholderPaint.setColor(placeholderColor); // default 0x10000000
    canvas.drawCircle(
        bounds.centerX(), bounds.centerY(),
        bounds.width() * .4f,
        placeholderPaint);
    return;
}
```

| Role | Value |
| ---- | ----- |
| Shape | Circle |
| Radius | `0.4 × bounds.width` (glyph draw bounds, not full cell pitch) |
| Fill | `placeholderColor` default `0x10000000`; spannable path tints via `0x10ffffff & textColor` |
| Motion | None — static until bitmap page loads |

`AnimatedEmojiDrawable.placeholderPaint` (`0x0fffffff` / `0x0f000000`) exists for theme updates; keyboard draw path for animated leaves goes through `ImageReceiver`, not this circle.

## Animated emoji — thumb-first, not circle

Keyboard grid: `emojiCacheType = CACHE_TYPE_KEYBOARD`, spans →
`AnimatedEmojiSpan.update` → shared `AnimatedEmojiDrawable` map on the grid.

While document media is not ready, `ImageReceiver` paints `staticThumbDrawable`
(often `DocumentObject.getSvgThumb(..., alpha ≈ 0.2)`). That is the loading
stand-in — **shape of the sticker/emoji thumb**, not `Emoji`’s circle.

## Stickers — shaped loading wash

`LoadingStickerDrawable`: SVG alpha mask × horizontal `LinearGradient` translated
over ~1800ms. Use this pattern for **sticker** leaves, not as the default for
unicode emoji cells.

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
