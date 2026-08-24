# panel_catalog

Extent-scroll catalog body with recycled paint leaves for keyboard-panel
surfaces (emoji / stickers / GIFs).

## Contract

- **Viewport** — `PanelCatalogViewport` (`LeafRenderObjectWidget`) +
  `RenderPanelCatalog` (package-private engine)
- **Extent scroll** — absolute `PanelCatalogController.offset` against known
  content height; layout fills parent constraints
- **Paint leaves** — no per-cell `StatefulWidget` default; visible-band asset
  bind/recycle
- **Data** — `CatalogDataSource` with `addDataListener` / `notifyDataChanged`
  (no streams); fetch stays in the source
- **Assets** — readiness from `catalog_assets`; leaf identity is
  `CatalogAssetKey` via `CatalogLeaf.assetKey`
- **Placeholders** — circle (unicode), thumb-first / shaped wash reserved

Shell chrome (strip, search, tabs) lives outside this package.

## Layout

```text
lib/
  panel_catalog.dart          # public barrel (no RenderObject export)
  src/
    model/                    # leaf, section, presentation
    data/                     # CatalogDataSource + fake
    viewport/                 # controller, widget, RO, paint/bind/slots
```
