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
  smooth scroll when the far-path distance gate passes (`spanCount × 9`
  flat-row rule); `isSectionJumpActive` for host strip-sync gating
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
- **Placeholders** — circle (unicode), thumb-first / shaped wash reserved

Shell chrome (strip, search, tabs, pickers) lives outside this package.

## Theme

Wrap the catalog subtree in [PanelCatalogTheme] with [PanelCatalogThemeData]:

```dart
PanelCatalogTheme(
  data: PanelCatalogThemeData.light, // or .dark / copyWith
  child: PanelCatalogViewport(/* … */),
)
```

[PanelCatalogViewport] resolves tokens from [PanelCatalogTheme.of] each build
(placeholder, press highlight, section headers, stand-in geometry, document stub).

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
