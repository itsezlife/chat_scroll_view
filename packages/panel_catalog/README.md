# panel_catalog

Extent-scroll catalog body with recycled paint leaves for keyboard-panel
surfaces (emoji / stickers / GIFs).

## Contract

- **Viewport** — `PanelCatalogViewport` (`LeafRenderObjectWidget`) +
  package-private `RenderPanelCatalog` engine
- **Extent scroll** — absolute `PanelCatalogController.offset` against known
  content height; layout fills parent constraints; drag-end ballistic fling;
  pointer-down while flinging cancels coast and suppresses leaf pick for that
  pointer
- **Section jump** — `PanelCatalogController.jumpToSection` with near-path
  smooth scroll when the far-path distance gate passes (`≤ 9` flat rows;
  `spanCount × 9` in per-cell adapter space); `isSectionJumpActive`
  for host strip-sync gating
- **Paint leaves** — no per-cell `StatefulWidget` default; visible-band asset
  bind/recycle
- **Hit-test** — viewport-owned pointer → `CatalogLeaf`; shell callbacks
  for tap and long-press start/move/end; optional `leafLongPressEligible`
  per leaf (plain glyphs stay tap-only)
- **Theme** — [PanelCatalogTheme] scopes [PanelCatalogThemeData]: placeholder
  fill, press highlight, section header color, stand-in corner radius,
  document stub fill; [PanelCatalogThemeData.lerp] for transitions
- **Data** — `CatalogDataSource` with `addDataListener` / `notifyDataChanged`
  (no streams); fetch stays in the source
- **Assets** — readiness from `catalog_assets`; leaf identity is
  `CatalogAssetKey` via `CatalogLeaf.assetKey`
- **Baked glyphs** — with a `CatalogAssetCache.glyphAtlas`, unicode leaves are
  drawn as sprites from atlas pages, one batched draw per page; the circle
  placeholder shows until a glyph is baked. Without an atlas (the web) glyphs
  are paragraphs. `panel_catalog_diagnostics.dart` counts glyphs drawn as text:
  `0` where emoji are baked
- **Placeholders** — circle (unicode until baked), thumb-first / shaped wash
  reserved

| The host provides | The host must not |
| --- | --- |
| A `CatalogAssetCache` whose `glyphAtlas` plans every glyph the data source shows (none on the web) | Expect a glyph outside the atlas to draw as text: it stays a placeholder |
| The atlas's `panelVisible` / `panelOpening` signals (the viewport reports scrolling and the visible band itself) | Start a bake on the web, or run one beside the open animation |
| A fresh atlas (and cache) when the planned glyphs change | Dispose the atlas while a viewport still draws from it and expect the last frame to survive: the cells show placeholders |

Shell chrome (strip, search, tabs, pickers) lives outside this package.

## Theme

Wrap the catalog subtree in [PanelCatalogTheme] with [PanelCatalogThemeData]:

```dart
PanelCatalogTheme(
  data: PanelCatalogThemeData.light, // or .dark / copyWith
  child: PanelCatalogViewport(/* … */),
)
```

[PanelCatalogViewport] resolves [PanelCatalogTheme.of] into
[CatalogLeafPaintTheme] once per build (DPR included) and passes that snapshot
to the engine.

Pick preset from shell brightness:

```dart
data: PanelCatalogThemeData.forBrightness(brightness),
```

Animate light ↔ dark by rebuilding with [PanelCatalogThemeData.lerp]:

```dart
data: PanelCatalogThemeData.lerp(PanelCatalogThemeData.light, PanelCatalogThemeData.dark, t),
```

Disable press highlight only: `copyWith(leafPressHighlightColor: Color(0))`.

## Layout

```text
lib/
  panel_catalog.dart          # public barrel (no RenderObject export)
  src/
    model/                    # leaf, section, presentation
    data/                     # CatalogDataSource + fake
    theme/                    # PanelCatalogTheme + PanelCatalogThemeData
    viewport/                 # controller, widget, RO, paint/bind/slots
```
