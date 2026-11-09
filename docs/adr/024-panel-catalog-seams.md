# ADR 024: Panel catalog public seams

`panel_catalog` keeps its render object, stitch and near / far algorithms. Its
public seams change: layout becomes per section, a leaf becomes a value with an
opaque host tag, data arrives as an immutable snapshot, and the controller
attaches a position contract. This amends [ADR 006](006-panel-catalog-viewport.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — the snapshot is a `package:listen` `ValueListenable` and the scroll events a synchronous broadcast `Stream` ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Amended**: 2026-10-16 — mouse seams: secondary tap, per-kind long-press delay, pinned leaf, leaf bounds  
**Amended**: 2026-11-10 — the overscroll sink: the part of a drag past the top edge goes to the host on the tick it overflows, its release at the velocity of its own share (section *Amendment: the overscroll sink*)  
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (amended), [ADR 021](021-content-identity-and-collections.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 031](031-localization-accessibility-and-input.md)

## Decided

| Seam | Decision |
| ---- | -------- |
| Layout | A sealed per-section `SectionLayout`. `Grid(spanCount, cell aspect or extent, header extent, insets, textDirection)` now; other kinds (for example `Justified` rows for GIFs) can be added later. The viewport-wide `spanCount`, `cellExtent` and `headerExtent` become defaults. `insets` are physical sides; `textDirection` changes only the x order of cells and the header action. One atlas bakes one glyph size, so the host sizes it with `PanelCatalogViewport.largestGlyphBox` over the layouts it serves: larger cells never upscale it and smaller ones scale the same sprites down. |
| Leaf | A value: content key, descriptor paint facts (media form, kind-driven placeholder, size hint) and an opaque host `tag`. Equality covers key and facts; the tag is excluded from equality and from painting. Interaction callbacks return `CatalogLeafHit(sectionId, index, leaf)`. The instance-keyed side map is replaced by the tag, and `CatalogLeafPresentation` is deleted because it derives from stage and descriptor. Paint mode is never stored on the leaf. |
| Asset binding | The viewport derives `AssetSpec` (cell or glyph bounds times DPR; template decode mode from the descriptor) and `AssetProfile` (animate while visible and not paused; a scroll or a fling never pauses a leaf on screen, as in the reference panel grids, ticket 141), attaches through the asset cache and paints the `AssetPaintable`. The placeholder style comes from the descriptor: glyph is a circle, animated or custom is thumb-first, sticker is a shaped wash; a section may override spec preset or placeholder style. A paintable that exposes a sprite is drawn in one batched atlas draw per page; any other paintable paints itself. The viewport holds a page through its binding, never pixels. There is no `cacheType` enum and no downcast to a cache implementation. The cache comes from the host scope. |
| Failure and offline | No failed stand-in and no failed token. A leaf that fails or hangs keeps its placeholder; the sticker wash keeps animating while visible, gated by the shared playback clock and the global pause layers. |
| Sections | A header is a title (data title or presentation-mapped) plus an optional trailing action painted by the viewport and reported through `onSectionAction(sectionId, actionId)`. Section state mirrors collection state: loading or failed paints N skeleton leaves in the placeholder style with no error UI; empty shows a host message row; loaded shows leaves. The controller emits `SectionNearViewport(sectionId, edge)` so pages trigger loads and pagination. Non-grid rows (trending strip, search entry) are not designed; the sealed layout leaves room. |
| Controller | `ScrollController`-style. The render object attaches one position contract (offset, extents, `jumpTo`, `animateTo`, `scrollBy`, `jumpToSection`); commands call it, and when unbound they commit a target and apply it on attach. One typed scroll-event `Stream` (synchronous, broadcast) carries drag, fling, section jump and near-viewport events; settled events carry the visible leaf keys so visible-band priority keeps working. The five hand-rolled channels are deleted. |
| Data source | `CatalogDataSource` is replaced by a `ValueListenable` (`package:listen`) of an immutable `CatalogSnapshot` (sections), notifying once per assigned snapshot. The fake becomes a snapshot fake. |
| Theme | `PanelCatalogThemeData` stays a small viewport-owned paint-token class: placeholder style tokens (circle, thumb and wash colours, shimmer parameters), press highlight, selector radius, header style, skeleton colour. Failed and stub tokens are removed. `panel_catalog` does not depend on `chrome_foundation`; `panel_pages` maps foundation tokens to it in one adapter and scopes it with `PanelCatalogTheme`. |
| Mouse seams | Generic, so `panel_catalog` stays chrome-free: `onLeafSecondaryTap(hit, globalPosition)` for a mouse's right button (never a tap, a press animation or a long press); `leafLongPressDelay(hit, kind)` choosing a long-press delay per cell and pointer kind (null is the platform's, `Duration.zero` is at once; one recognizer per distinct delay); `pinnedLeaf`, which keeps one cell's hover wash and ignores the wheel while a host surface is open over it; and `PanelCatalogController.leafBoundsOf` / `viewportBounds` (global rectangles, through `CatalogScrollPosition`) so a host can place that surface. Only the primary button starts the press animation. What a right click or a held press opens is the page's. |
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

## Amendment: an adaptive grid

The reference desktop client sizes its emoji columns from the panel's width: as
many columns of a desired width as fit, the cell widened to share the room, the
remainder split as a margin.

| Area | Decision |
| ---- | -------- |
| Grid | `SectionLayout.grid` takes an optional `desiredCellWidth` and `cellHeightInset`. With them, `cols = max(floor(usable / desired), 1)`, `cellWidth = floor(usable / cols)`, `cellHeight = cellWidth - inset`, and `floor(remainder / 2)` is added to the leading padding. Without them the fixed column count and cell stay as they were. |
| Policy | `CatalogPagePolicy.layoutOf(collection, {arrangement})`: a page may lay a section out per arrangement. The emoji page asks for 37 px cells, 2 px shorter than wide, under `pointer`. |
| Glyph size | `SectionLayout.grid(glyphExtent:)` fixes the side of the glyph box instead of 0.72 of the cell's shorter side (held to that side); the leaf asks the cache for that box and draws in it, sprite, paragraph or placeholder alike. Content that fills its cell ignores it. |
| Drag | A mouse does not drag the catalogue; the wheel and the scrollbar scroll it. Touch, stylus and trackpad still drag. |

## Amendment: a desktop list's ink

| Area | Decision |
| ---- | -------- |
| Hover | `PanelCatalogThemeData.leafHoverHighlightSize` paints the hover wash as a box of that size centred in the cell (held to it) instead of the inset cell. The reference desktop client's is 34 x 32, radius 8, whatever the cell. |
| Press | `leafPressFeedback`: `inkAndScale` (the default: the press wash and the 0.8 shrink, a touch grid) or `none` (a desktop list: no wash, no shrink, the hover box stays on the pressed cell until release, and the leaf is chosen on release). |

## Amendment: where a header action is

`PanelCatalogController.sectionActionBoundsOf(sectionId)` (through
`CatalogScrollPosition.sectionActionBounds`): the button of a section header's
action in global coordinates, for a host to anchor what it opens.

## Amendment: the overscroll sink

A catalogue inside something that moves (a bottom sheet whose card is the
grid's own lead padding) had no way to hand on a drag it could not scroll:
`scrollBy` clamps at the top and drops the rest, so a pull down at the top
moved nothing, and the sheet's own drag detector lost every arena to the
grid's recognizer. Only the viewport knows whether its content is at the top
and how much of a tick it consumed, so the hand-over is a viewport seam,
shaped like the chat viewport's `ChatOverscrollSink`.

| Area | Decision |
| ---- | -------- |
| Seam | `PanelCatalogViewport.overscrollSink`: a `CatalogOverscrollSink` of `onStart`, `onDelta(pixels) -> taken` and `onEnd(velocity) -> bool`, in the finger's sign (positive pulls past the top). Top edge only: the catalogue's bottom edge has no host that moves. |
| Order | While content rests at the top (always, for content that fits) every drag tick is offered first, in both directions: the receiver moves before content until it declines, so a push up first undoes a pull. Away from the top only the part of a downward tick that content cannot scroll is offered, on the same tick that brings content to the top: nothing is held back at the edge, as a draggable sheet hands over. The return is clamped to the offer. |
| Release | `onEnd` is called once for a drag in which the sink took something (with `0` for a cancelled one), at the velocity of the sink's own share: estimated from the pixels it took against the ticks' event times, not from the finger's whole drag. A fast scroll that reaches the top and runs a little past it, slowing, is a slow pull: a receiver that dismisses on velocity springs back instead. `true` means the receiver settles the release and no content fling starts; `false` lets the content fling (it gave everything back and the finger went on to scroll). |
| Not offered | The mouse (it never drags the catalogue), the wheel, focus moves, a fling (one that reaches the top stops there) and programmatic motion. |
| Tests | `FakeCatalogOverscrollSink` and `CatalogOverscrollSinkContract.run` in `testing.dart`: a receiver takes no more than it is offered, declines a push while it holds nothing, gives back what it holds before declining, and takes the release exactly when it still holds a pull. Every receiver runs it (the pack sheet's drag owner does). |

Rejected: a rest before a pull (a pull past the top dropped until content
has rested there, 200 ms, so a scroll back to the top that runs on does not
close a sheet): on a device it read as the edge swallowing part of the drag
before the sheet moved. Measuring the release on the sink's own share covers
the case it was for, and a fling never reaches the sink. Also rejected:
porting a draggable-scrollable sheet that resizes its box and
couples through a framework `ScrollPosition` (the catalogue is not a
`Scrollable`, and two ballistic owners plus a relayout per drag frame would
replace a geometry that already works); a host `Listener` that guesses what
the grid consumed; the sheet's own detector winning the arena (it would take
every drag the grid should scroll).
