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
- **Section layout** — each `CatalogSection` may carry a sealed
  `SectionLayout` (`SectionLayout.grid`: columns, cell extent or cell aspect,
  header extent, insets). The viewport's `spanCount`, `cellExtent` and
  `headerExtent` are the defaults a section inherits; sections of different
  spans and cell sizes stack in one catalog. The visible window stays a binary
  search over one ascending slot list, so its cost follows the visible band,
  not the catalogue or the mix of layouts
- **Section jump** — `PanelCatalogController.jumpToSection` with near-path
  smooth scroll when the far-path distance gate passes (`≤ 9` flat rows, each
  section's rows counted at its own column count; `spanCount × 9` in per-cell
  adapter space); `isSectionJumpActive` for host strip-sync gating.
  `scrollOffsetForSectionHeader` is the landing offset of a section as painted
- **Paint leaves** — no per-cell `StatefulWidget` default; visible-band asset
  bind/recycle
- **Leaf** — `CatalogLeaf` is a value: content key, descriptor paint facts
  (semantic kind, media form, animated, tintable, size hint) and an opaque
  host `tag` that equality and painting ignore. It holds no readiness, paint
  mode or sprite
- **Hit-test** — viewport-owned pointer → `CatalogLeafHit(sectionId, index,
  leaf)`; the cell is the identity, so the same key in two sections is two
  hits. Shell callbacks for tap and long-press start/move/end; optional
  `leafLongPressEligible` per cell (plain glyphs stay tap-only)
- **Theme** — [PanelCatalogTheme] scopes [PanelCatalogThemeData], a small
  token class the viewport owns: placeholder colours (circle, thumb, wash and
  its sweep period and highlight), skeleton colour, press highlight and
  selector radius, section header style; [PanelCatalogThemeData.lerp] for
  transitions. The package depends on no chrome or design-system package: a
  page that has foundation tokens maps them onto this class in one place
- **Data** — an immutable `CatalogSnapshot` (sections) published through a
  `ValueObservable<CatalogSnapshot>` from `content_model`, one notification per
  logical mutation (group steps in the owner's `batch`); fetch stays in the
  owner. `package:panel_catalog/testing.dart` has `FakeCatalogSnapshotSource`
  and `FakeCatalogScrollPosition`
- **Assets** — the viewport attaches each visible leaf through the host's
  `AssetCacheScope` as `attach(key, spec, profile)` and paints the
  `AssetPaintable` of the binding. The spec is the leaf's glyph box in physical
  pixels at the density of the view the viewport sits in (a template decode for
  a tintable leaf); the profile animates only for an animated leaf, and such a
  leaf plays only while it is in the painted window and no fling runs. Leaves
  outside the window plus one cell of overscan detach. The cache comes from the
  host; the viewport names no cache implementation, no atlas and no
  `cacheType`
- **Content box** — a leaf is asked for, and drawn in, a centred square of its
  cell: the glyph box (`kCatalogGlyphBoxFraction` of the shorter side) for
  emoji, the whole cell for a sticker, mask or GIF (`CatalogLeaf.contentBox`).
  A `CatalogSection` may override it (`contentBox`) and the placeholder style
  (`placeholderStyle`) for all its leaves
- **Painting what a binding has reached** — a paintable with a sprite is
  queued and drawn in one batched atlas draw per page; any other paints
  itself. Content that was not there at attach fades in over its placeholder
  (150 ms); content that was (a memory hit) does not. A leaf that fails or
  hangs keeps its placeholder: there is no failed stand-in and no failed token
- **Baked glyphs** — a scope whose glyph source is an atlas gives every unicode
  leaf a sprite once its page is baked, and the circle until then, however long
  that takes. A scope with no glyph source and a `TextGlyphProducer` draws the
  glyph as text (the web), through the same paintable seam. The viewport holds
  an atlas page only through its binding (a count, never pixels) and never
  keeps a sprite beyond one paint. `panel_catalog_diagnostics.dart` counts
  glyphs drawn as text: `0` where emoji are baked
- **Largest glyph box** — a glyph is drawn in `kCatalogGlyphBoxFraction` of
  its cell's shorter side. An atlas bakes one size, so the host sizes it with
  `largestCatalogGlyphBox` over the layouts it serves: larger cells are never
  upscaled, smaller ones scale the same sprites down, and there is no second
  atlas
- **Placeholders** — derived from the leaf's facts (`placeholderStyle`): circle
  (glyph, until baked), shaped wash (sticker: one gradient per paint pass
  sweeps every wash on screen together, and stops while the scope's clock is
  paused), thumb-first (other media: the binding's own thumbnail once it has
  one)

| The host provides | The host must not |
| --- | --- |
| A `ValueObservable<CatalogSnapshot>` and a `PanelCatalogController` (the host creates and disposes both) | Mutate a published snapshot or notify once per leaf: publish a new snapshot per logical mutation |
| Listeners on `controller.events` for chrome that follows scrolling | Call the controller's `attach` / `detach` / `publish`: they belong to the viewport |
| An `AssetCacheScope` (host-created and disposed) whose `glyphSource` is an atlas planning every glyph the data source shows, baked at `largestCatalogGlyphBox` of the layouts it serves; on the web no source and a `TextGlyphProducer` | Expect a glyph outside the atlas to draw as text: it stays a placeholder; build a second atlas for a section with other cell sizes |
| Stable section ids and, where the host needs to recognise a cell, a `tag` on the leaf | Identify a cell by its content key alone (the same key can be in several sections), or key a side map by leaf instance |
| The bake's three signals, and a listener on `controller.events` that calls the atlas (`reportScrolling` on `PanelCatalogScrollingChanged`, `prioritise` on `PanelCatalogScrollSettled`): the viewport tells no atlas anything | Start a bake on the web, or run one beside the open animation |
| A new atlas (and cache) when the planned glyphs change, built from the old one's `retire()` so the cells do not blank | Dispose the atlas while a viewport still draws from it and expect the last frame to survive: the cells show placeholders |

Shell chrome (strip, search, tabs, pickers) lives outside this package.

Decisions: [ADR 006](../../docs/adr/006-panel-catalog-viewport.md) (the
catalog viewport and its amendment on baked glyphs),
[ADR 024](../../docs/adr/024-panel-catalog-seams.md) (per-section layout, the
leaf value and its hit, snapshot data and the attach-and-position controller).

## Theme

Wrap the catalog subtree in [PanelCatalogTheme] with [PanelCatalogThemeData]:

```dart
PanelCatalogTheme(
  data: PanelCatalogThemeData.light, // or .dark / copyWith
  child: PanelCatalogViewport(/* … */),
)
```

[PanelCatalogViewport] resolves [PanelCatalogTheme.of] into
a density-resolved paint snapshot once per build and passes it to the engine.

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
    model/                    # leaf, leaf hit, section, section layout
    data/                     # CatalogSnapshot
    testing/                  # fakes, exported by lib/testing.dart only
    theme/                    # PanelCatalogTheme + PanelCatalogThemeData
    viewport/                 # controller, widget, RO, paint/bind/slots
```
