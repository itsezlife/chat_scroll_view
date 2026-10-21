# ADR 006: Panel Catalog Viewport (sibling to Chat Scroll)

Keyboard-panel emoji / stickers / GIFs get their own **Panel Catalog Viewport** —
a thin extent-scroll RenderObject engine with paint leaves and
**stitch** far jumps — not `SuperSliverList` forever and not a fork of Chat
Scroll’s message-id / anchor model. Assets live in a **global catalog asset
cache** shared with chat; catalog DS notifies like `ChatDataSource` but does
not own decode bytes. Monorepo: root `packages/`; `chat_scroll_view` remains at
repo root. The package set, the cache contract and the public seams are
amended by [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md)
and [ADR 024](024-panel-catalog-seams.md); the baked glyph atlas is described
in the [Amendment](#amendment-baked-glyph-atlas-and-shared-asset-scope).

**Status**: Accepted (amended 2026-10-16: baked glyph atlas and shared asset scope, see [Amendment](#amendment-baked-glyph-atlas-and-shared-asset-scope); package set amended by [ADR 020](020-package-topology.md), asset cache by [ADR 022](022-asset-cache-and-media-pipeline.md), public seams by [ADR 024](024-panel-catalog-seams.md))  
**Date**: 2026-08-24  
**Amended**: 2026-10-16 — unicode emoji are baked into atlas pages and drawn as batched sprites; asset cache shared through a host scope; per-section layout; chrome and package set replaced by the shell, pages and presentation packages

## Decided

| Topic         | Decision                                                                                                                                                                                                              |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Context       | Sibling **Panel Catalog Viewport** ([glossary](../panel-catalog/CONTEXT.md)); not “Media Grid” (collides with chat attachments)                                                                                       |
| Ownership     | Viewport = catalog body only; chrome around it is **KeyboardPanel** (ADR 007; was “catalog shell”) = strip / search / tabs / pickers / DS wiring                                                                      |
| Geometry      | **Extent scroll** (absolute offset + known/estimated content height)                                                                                                                                                  |
| Leaves        | **Paint leaf** pool + **viewport-owned hit-test**; no per-cell StatefulWidget default                                                                                                                                 |
| Leaf gestures | Tap and long-press start/move/end callbacks to **KeyboardPanel** with [CatalogLeaf] identity; optional **long-press eligibility** predicate; **fling-cancel suppress**; painted press scale + list-selector highlight |
| Theme         | **[PanelCatalogTheme]** + **[PanelCatalogThemeData]** — package inherited theme for placeholder fill and press chrome; [PanelCatalogThemeData.lerp] for transitions                                                   |
| Placeholders  | Kind-specific: **circle** (unicode, until its glyph is baked), **thumb-first** (animated), **shaped wash** (stickers) — see [leaf-placeholder.md](../panel-catalog/leaf-placeholder.md) and the Amendment      |
| Far path      | [CatalogFarStitch] when not attached and flat-row distance `> 9` (`spanCount × 9` in per-cell adapter space; or animations off). Capture → teleport → dual-translate; not naked `jumpTo`                              |
| Near path     | [PanelCatalogController.jumpToSection] + [CatalogNearScroll] (220ms decelerate). Landing under viewport [padding.top]                                                                                              |
| Section jump  | Flat-row gate ([CatalogSectionNavigation.farPathDistanceGateFactor] = 9 rows, not `span × 9`); [isSectionJumpActive] for shell strip-sync gating; near writes silent [correctOffset] only                                                     |
| Assets        | **Global catalog asset cache** (`packages/catalog_assets`); panel + chat bind/paint only; unicode glyphs are **baked sprites** on atlas pages (Amendment)                                                            |
| Data          | Parallel catalog DS + `addDataListener` / `notifyDataChanged`; fetch not in the viewport                                                                                                                              |
| v1 ship       | Unicode catalog + stitch + paint leaves; leaf contract ready for document-backed / animated                                                                                                                           |
| Packages      | Root `packages/` for catalog + chrome/data; `example/` is the app; `chat_scroll_view` remains at repo root                                                                                                            |

## Rejected

| Alternative                                                          | Why not                                                         |
| -------------------------------------------------------------------- | --------------------------------------------------------------- |
| Extend Chat Scroll glossary / anchor origin                          | Wrong identity model for a sectioned catalog                    |
| Far path = `jumpTo`                                                  | Loses scroll continuity (far jumps must stitch)                 |
| One generic shimmer for all leaves                                   | Leaf kinds need three different loading paints                  |
| Panel-private drawable cache                                         | Blocks reuse in chat inline emoji / stickers / GIFs             |
| Engine inside `chat_scroll_view` or forever under `example/packages` | Wrong bounded context; hides shared product surface             |
| Big-bang move of chat into `packages/` with v1                       | Unrelated churn; defer                                          |

## Amendment: baked glyph atlas and shared asset scope

Two efforts change this decision together, so they are recorded once: the
baked glyph atlas (why a colour-glyph fling janked, and the pipeline that
removes it) and the package-architecture seams (shared cache through a scope,
per-section layout, snapshot data, attach-and-position controller). The seam
contracts are decided in [ADR 022](022-asset-cache-and-media-pipeline.md) and
[ADR 024](024-panel-catalog-seams.md); this section keeps the panel-side view.

Each row below says whether it is **built** (in the packages today) or
**pending** (decided here and in those ADRs, not yet in the packages). Every
row is built.

### Changes to the Decided table

| Topic | Before | After | State |
| ----- | ------ | ----- | ----- |
| Assets | Process-wide **global catalog asset cache** shared with chat | **App-wide asset cache, host-created and provided through a scope**; no static singleton. The viewport and chat bind and paint only ([ADR 022](022-asset-cache-and-media-pipeline.md)). | Built |
| Presentation | Readiness drives presentation (ready / loading / failed per leaf) | The binding's stage is used only for crossfade. The placeholder is derived from the descriptor (media form, kind). There is no visible failed stage: a leaf that fails or hangs keeps its placeholder. | Built |
| Layout | Viewport-wide span count, cell extent, header extent | **Per-section layout** (sealed `SectionLayout`; `Grid` now); the viewport-wide values are the defaults ([ADR 024](024-panel-catalog-seams.md)). | Built |
| Leaf, data, controller | Leaf class hierarchy; parallel data source with listener channels; five controller channels | Leaf value with an opaque host tag and positional hit identity; snapshot data source on a `package:listen` `ValueListenable`; attach-and-position controller. Public seams only: render object, stitch and near / far invariants are unchanged ([ADR 024](024-panel-catalog-seams.md)). | Built |
| Paint surface | Bound drawable at the stage reached | A binding exposes an **optional sprite** (atlas page handle + source rectangle). The viewport draws the sprites of one atlas page in **one batched atlas draw**; a leaf without a sprite paints itself. | Built (the sprite capability sits on `AssetPaintable`, [ADR 022](022-asset-cache-and-media-pipeline.md)) |
| Chrome and packages | Chrome around the viewport is **KeyboardPanel** ([ADR 007](007-keyboard-panel-controller.md)); packages are `catalog_assets`, `panel_catalog`, `emoji_data`, `chat_chrome` | Chrome is the **panel shell** with **pages** and a **panel presentation** ([ADR 025](025-panel-shell-and-pages.md), [ADR 028](028-panel-presentation.md)); the package set is [ADR 020](020-package-topology.md). Leaf callbacks return a positional leaf hit. | Built |
| Unicode glyph | Painted from a paragraph cache | **Baked glyph** (sprite) on a **glyph atlas page**. On a baking platform emoji are never drawn as text at scroll time and a paragraph is never a fallback. Web has no atlas and keeps the paragraph path, with a bounded, disposed cache. | Built |
| Placeholder (circle) | Unicode never shows a circle | Unicode shows the circle placeholder until its glyph is baked, with no time limit; with a valid disk cache the circle lasts at most 500 ms after a cold start. | Built |
| Warm-up | `warmAhead` rasterises the visible band offscreen on open | Removed. It did not make the first fling cheaper, and where emoji are baked it built paragraphs that are never drawn. | Built |

### Sprites and atlas pages

- A leaf binding resolves to a sprite and holds the page, never the pixels, so
  eviction cannot corrupt a live binding. Pages are reference-counted per page
  by a **page residency** shared by the atlas and the cache bindings.
- Static glyph pages are immutable once composed and 2048 x 2048. The baked
  glyph size is one tunable constant capped at 72 px, with a 2 px transparent
  gutter (about 676 cells per page, three pages for the current catalogue).
- Resident atlas memory is at most 64 MiB while the panel is open, except
  while a rebake draws the previous pages behind it (an art, catalogue or
  density change): both sets are resident until the swap, about twice that for
  a few seconds, which is the price of no visible gap. The previous set is
  counted with the resident bytes and released with them on memory pressure.
  Pages stay resident for a 60 s **retention** after the last holder leaves and
  are released at once on memory pressure; a released page is read back from
  the page store, one page per frame. Escalation if the size cap fails a visual check on a device
  class: windowed residency (a few pages resident, the rest reloaded from the
  disk cache), not a higher ceiling.
- A second, dynamic page pool for animation frames may join later under the
  same sprite abstraction; it does not share pages with static glyph pages.

### Bake

- The **bake** rasterises exactly the glyphs the data layer supplies (the
  engine does not detect missing glyphs) into atlas pages on the root isolate,
  behind a rasteriser seam, paced across frames by a governor that adapts
  glyphs per frame to measured frame time. It bakes the page holding the
  visible band first and pauses while the panel is hidden, opening, or
  scrolling (including the fling).
- Pages persist behind a page-store seam. The cache key is: system emoji art
  version signal + screen density + baked cell pixel size + atlas layout
  version + catalogue content hash. An art or catalogue change keeps the old
  pages drawing while the new set bakes into a staged generation, then swaps
  every sprite in one step; a density, cell-size or layout-version change
  discards them and shows circles.
- The art version signal is a pixel fingerprint of a few sentinel glyphs drawn
  by the bake's own rasteriser, one per frame, once per launch. It needs no
  native call; the OS version string is at most a supplementary component a
  host may add to it. The glyph-support probe produces it and the host hands it
  on as the cache key component, so it is rendered once for both.
- The glyph-support probe is pure Dart in the emoji data layer. It shares the
  bake pass: each glyph is rasterised once into a strip and the probe is shown
  its cell, so it adds no rasterising pass. The atlas plans the unfiltered
  glyph list; the grid hides unsupported glyphs by filtering its data, so the
  cache key never depends on the probe's result. The probe's verdicts are
  persisted through the key-value store under the art version, so a launch
  that restores baked pages (where the bake draws nothing) still has them. The
  native plugin is gone from the emoji data package.

### Scroll-time hardening

The viewport is its own repaint boundary, allocates no per-leaf paint objects
per frame beyond the placeholder shapes, finds the visible window in time
proportional to the visible band, and no longer has an offscreen warm-up.

### Why

On a flagship 120 Hz phone the first pass over the catalogue dropped 21 of 455
frames, worst frame 68 ms, while every later pass was clean (prototype
measurements). The system emoji font rasterises each colour glyph
synchronously on the raster thread the first time it appears (and on every
frame on the Skia renderer); a plain Latin letter in its place removed all of
it. Baking pays that cost once, paced across frames and persisted, and the
batched atlas draw costs a small fraction of a frame.

### Acceptance

On the reference device, a cold first pass over the whole catalogue drops no
frame over one vsync budget and keeps raster p99 at or below 2 ms; the panel
open animation meets the same bar; three of three cold launches, for the bare
panel, the panel over the chat screen and a first run with no cache. A headless
test cannot see raster cost and is not used to claim smoothness. Only the
reference device gates; other devices and platforms are best effort.

### Amendment: rejected

| Alternative | Why not |
| ----------- | ------- |
| Paragraph paintable as the unicode glyph form | The system emoji font rasterises each colour glyph synchronously on the raster thread the first time it appears; a warm-up did not remove it. |
| Per-leaf-binding ownership of glyph pixels | Eviction can corrupt live bindings; pages cannot be drawn in one batch. |
| Native font-version call in the emoji data package | Native code is removed there; the pixel fingerprint needs none. |
| Windowed page residency or a higher ceiling by default | The 72 px cap fits 64 MiB with no visible difference at actual size; windowing is the escalation. |
| Reordering cells so the visible band bakes first | A persisted page must still match its glyphs; priority works per page. |
| Bundled emoji art | Loses the system look shared with composer and chat text; kept only as a fallback if the bake fails its measurement. |

## Related

- Chat stitch / load-gate: [ADR 005](005-stitch-far-path-and-load-gate.md) (chat-only rules; panel does **not** inherit message load-gate by default)
- Context map: [CONTEXT-MAP.md](../../CONTEXT-MAP.md)
- Package set, asset cache and seam contracts: [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 024](024-panel-catalog-seams.md)
- Glyph atlas vocabulary: [Panel Catalog glossary](../panel-catalog/CONTEXT.md) (Glyph atlas group); cache and invalidation QA: [qa-glyph-cache.md](../panel-catalog/qa-glyph-cache.md)
