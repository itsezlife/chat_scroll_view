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
- **Controller** — scroll-controller style: the viewport attaches one
  `CatalogScrollPosition` (offset, extents, `jumpTo`, `animateTo`, `scrollBy`,
  `jumpToSection`) and the controller forwards commands to it. With no
  viewport attached, commands commit a target and the viewport that attaches
  starts from it ([ADR 007](../../docs/adr/007-keyboard-panel-controller.md)
  semantics); `jumpToSection` stays pending until a viewport is laid out. One
  typed `controller.events` Observable carries drag, fling, programmatic jump,
  animate, section jump and offset events, plus two derived activity facts:
  `PanelCatalogScrollingChanged` (at once when the catalogue starts moving,
  after one quiet frame when it stops) and `PanelCatalogScrollSettled` (the
  visible `ContentKey`s, top first) so a page can pace background work
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
- **Data** — an immutable `CatalogSnapshot` (sections) published through a
  `ValueObservable<CatalogSnapshot>` from `content_model`, one notification per
  logical mutation (group steps in the owner's `batch`); fetch stays in the
  owner. `package:panel_catalog/testing.dart` has `FakeCatalogSnapshotSource`
  and `FakeCatalogScrollPosition`
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
| A `ValueObservable<CatalogSnapshot>` and a `PanelCatalogController` (the host creates and disposes both) | Mutate a published snapshot or notify once per leaf: publish a new snapshot per logical mutation |
| Listeners on `controller.events` for chrome that follows scrolling | Call the controller's `attach` / `detach` / `publish`: they belong to the viewport |
| A `CatalogAssetCache` whose `glyphAtlas` plans every glyph the data source shows (none on the web) | Expect a glyph outside the atlas to draw as text: it stays a placeholder |
| The atlas's `panelVisible` / `panelOpening` signals (the viewport reports scrolling and the visible band itself) | Start a bake on the web, or run one beside the open animation |
| A new atlas (and cache) when the planned glyphs change, built from the old one's `retire()` so the cells do not blank | Dispose the atlas while a viewport still draws from it and expect the last frame to survive: the cells show placeholders |

Shell chrome (strip, search, tabs, pickers) lives outside this package.

Decisions: [ADR 006](../../docs/adr/006-panel-catalog-viewport.md) (the
catalog viewport and its amendment on baked glyphs),
[ADR 024](../../docs/adr/024-panel-catalog-seams.md) (snapshot data and the
attach-and-position controller).

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
  testing.dart                # opt-in fakes
  src/
    model/                    # leaf, section, presentation
    data/                     # CatalogSnapshot
    testing/                  # fakes, exported by lib/testing.dart only
    theme/                    # PanelCatalogTheme + PanelCatalogThemeData
    viewport/                 # controller, widget, RO, paint/bind/slots
```
