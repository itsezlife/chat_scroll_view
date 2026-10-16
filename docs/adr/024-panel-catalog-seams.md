# ADR 024: Panel catalog public seams

`panel_catalog` keeps its render object, stitch and near / far algorithms. Its
public seams change: layout becomes per section, a leaf becomes a value with an
opaque host tag, data arrives as an immutable snapshot, and the controller
attaches a position contract. This amends [ADR 006](006-panel-catalog-viewport.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (amended), [ADR 021](021-content-identity-and-collections.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 031](031-localization-accessibility-and-input.md)

## Decided

| Seam | Decision |
| ---- | -------- |
| Layout | A sealed per-section `SectionLayout`. `Grid(spanCount, cell aspect or extent, header extent, insets, textDirection)` now; other kinds (for example `Justified` rows for GIFs) can be added later. The viewport-wide `spanCount`, `cellExtent` and `headerExtent` become defaults. `insets` are physical sides; `textDirection` changes only the x order of cells and the header action. One atlas bakes one glyph size, so the host sizes it with `largestCatalogGlyphBox` over the layouts it serves: larger cells never upscale it and smaller ones scale the same sprites down. |
| Leaf | A value: content key, descriptor paint facts (media form, kind-driven placeholder, size hint) and an opaque host `tag`. Equality covers key and facts; the tag is excluded from equality and from painting. Interaction callbacks return `CatalogLeafHit(sectionId, index, leaf)`. The instance-keyed side map is replaced by the tag, and `CatalogLeafPresentation` is deleted because it derives from stage and descriptor. Paint mode is never stored on the leaf. |
| Asset binding | The viewport derives `AssetSpec` (cell or glyph bounds times DPR; template decode mode from the descriptor) and `AssetProfile` (animate only while visible and not paused or flinging), attaches through the asset cache and paints the `AssetPaintable`. The placeholder style comes from the descriptor: glyph is a circle, animated or custom is thumb-first, sticker is a shaped wash; a section may override spec preset or placeholder style. A paintable that exposes a sprite is drawn in one batched atlas draw per page; any other paintable paints itself. The viewport holds a page through its binding, never pixels. There is no `cacheType` enum and no downcast to a cache implementation. The cache comes from the host scope. |
| Failure and offline | No failed stand-in and no failed token. A leaf that fails or hangs keeps its placeholder; the sticker wash keeps animating while visible, gated by the shared playback clock and the global pause layers. |
| Sections | A header is a title (data title or presentation-mapped) plus an optional trailing action painted by the viewport and reported through `onSectionAction(sectionId, actionId)`. Section state mirrors collection state: loading or failed paints N skeleton leaves in the placeholder style with no error UI; empty shows a host message row; loaded shows leaves. The controller emits `SectionNearViewport(sectionId, edge)` so pages trigger loads and pagination. Non-grid rows (trending strip, search entry) are not designed; the sealed layout leaves room. |
| Controller | `ScrollController`-style. The render object attaches one position contract (offset, extents, `jumpTo`, `animateTo`, `scrollBy`, `jumpToSection`); commands call it, and when unbound they commit a target and apply it on attach. One typed scroll-event `Observable` carries drag, fling, section jump and near-viewport events; settled events carry the visible leaf keys so visible-band priority keeps working. The five hand-rolled channels are deleted. |
| Data source | `CatalogDataSource` is replaced by a value-carrying `Observable` of an immutable `CatalogSnapshot` (sections), notifying once per logical mutation. The fake becomes a snapshot fake. |
| Theme | `PanelCatalogThemeData` stays a small viewport-owned paint-token class: placeholder style tokens (circle, thumb and wash colours, shimmer parameters), press highlight, selector radius, header style, skeleton colour. Failed and stub tokens are removed. `panel_catalog` does not depend on `chrome_foundation`; `panel_pages` maps foundation tokens to it in one adapter and scopes it with `PanelCatalogTheme`. |
| Accessibility | Windowed leaf semantics, roving-focus controller API, focus highlight token and cursor, as [ADR 031](031-localization-accessibility-and-input.md) specifies. |

Render-object internals the seams imply (per-section projection, hit
identity, semantics) keep the near / far invariants in
[docs/panel-catalog](../panel-catalog/CONTEXT.md) and the benchmark baseline.

## Why

- iOS gives each item group its own layout type, Desktop varies sticker grids per set, and Android lazy-loads sets near the viewport and keeps skeletons offline.
- The old seams had an instance-keyed leaf meta, closed two-variant hierarchies, `presentationFor` switches, a downcast to the in-memory cache, and five controller channels.
- Hosts and pages need positional hit identity, because the same key can appear in several sections.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Viewport-wide geometry with one viewport per panel type; per-leaf flex sizing now | Sticker sets and emoji groups differ per section; flex sizing is not needed yet |
| Identity-only leaf with host-owned (section, key) maps; a generic `CatalogLeaf<T>` | Side maps drift from the leaves; a type parameter spreads through the whole viewport |
| Explicit per-section spec and placeholder declarations everywhere; pluggable leaf-painter strategies | Derivation from the descriptor covers the cases; plug-in painters bypass batching |
| Title-only headers with host overlays; designing non-grid rows before the sticker panel is specified | Overlays fight the viewport's paint; speculative design |
| Keeping the controller channels or leaving the plumbing | Five mechanisms for one concern |
| `panel_catalog` depending on foundation tokens; moving viewport tokens into foundation | Couples the engine to chrome theming |

## Related

- Glossary: [Panel Catalog](../panel-catalog/CONTEXT.md)
- Asset side: [ADR 022](022-asset-cache-and-media-pipeline.md)
