# ADR 022: Asset cache and media pipeline contract

`catalog_assets` is a host-created, app-wide cache that turns a content key and
an asset spec into an `AssetPaintable`. Fetching, decoding, playback and
budgets sit behind seams the host and adapter packages fill. Unicode glyphs
are one media form of that pipeline: a baked sprite on a glyph atlas page.

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (replaces its process-wide cache wording; the atlas amendment there is the panel-side view of this ADR), [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 024](024-panel-catalog-seams.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Paint surface | A binding yields an `AssetPaintable`: `paint(canvas, rect, context)` with tint, opacity and playback time in the context. The adapter picks the representation (decoded image or frame, vector composition, baked glyph sprite). The paintable has an optional **sprite capability**: an atlas page handle plus a source rectangle. A consumer that batches (the panel catalog viewport) draws every sprite of one page in one batched atlas draw; a paintable without a sprite paints itself. A placeholder paintable is always available and synchronous. |
| Glyph form | Unicode glyphs are the built-in glyph media form: a **baked sprite** on a **glyph atlas page**, never a paragraph at scroll time on baking platforms. Until its cell is baked the binding presents the placeholder (circle) with no time limit; once baked it is final and yields a sprite. The glyph set is what the data layer's glyph-support seam supplies; the atlas bakes the list it is planned with and does not detect missing glyphs. A platform that does not bake (web) selects a paragraph-painting strategy behind the viewport's painter seam, not a platform fork in the cache. There is no special path and no downcast. |
| Atlas ownership | A host or page plans and creates the glyph atlas. The atlas owns its **page residency**. The cache reaches it through one narrow seam, a glyph sprite source (`spriteOf`, `holdPageOf`, page listener) that the atlas implements and the host registers with the scope. The cache does not create atlases and does not know the planned glyph list. |
| Page residency | Pages are shared state, not binding state. A binding resolves to a sprite and takes a hold on the page at attach and releases it at detach; it never holds pixels. Hold counts belong to the holder, so evicting or clearing a cache entry under a live binding never changes a count. Static glyph pages are immutable once composed. A separate dynamic page pool for animation frames may be added later; it shares the sprite abstraction, not pages. Pages are 2048 x 2048 with a 2 px transparent gutter, and the baked glyph size is one tunable constant capped at 72 px. |
| Memory | Resident static pages stay within 64 MiB while the panel is open, except during a rebake, where the previous set stays resident until the swap (about twice that for a few seconds). Pages stay resident for a 60 s retention after the last hold ends and are all released at once on memory pressure, pinned or not; a released page is read back from the page store, one page per frame. |
| Bake | The baker rasterises glyphs on the root isolate behind a rasteriser seam, paced by a governor that adapts glyphs per frame (1 to about 16) to measured frame time. It bakes the page holding the visible band first, then the nearest pages, and composes strips into pages one page per frame. The host owns the pause signals (panel hidden, panel opening, scrolling including the fling); the bake only reads them. The glyph probe ([ADR 023](023-data-layering-and-persistence.md)) shares the bake pass, so no glyph is rasterised twice. |
| Persistence | Pages persist behind a page-store seam. The cache key is system emoji art version signal, screen density, baked cell pixel size, atlas layout version and a hash of the planned glyph list. An art or catalogue change keeps the old pages drawing while the new set bakes into a staged generation, then swaps every sprite at once. A density, cell-size or layout-version change discards them and shows circles. The art version signal is a pixel fingerprint of a few sentinel glyphs drawn by the bake's own rasteriser. Rasteriser and page store ship fakes in `testing.dart`. |
| Entry identity | Content key plus `AssetSpec`: pixel size at DPR, template or tint decode mode, and variant (first frame only or full). Surfaces are named presets of spec and profile owned by the host and packages. The old `keyboard` / `messages` enum is gone. |
| Behaviour | A per-attach `AssetProfile` (animate, loop, autoplay first frame, corner radius). It does not split cache entries. |
| Attach | `attach(key, spec, profile)`. An unknown descriptor sends the core to the host `ContentResolver`; readiness stays `none` until it resolves. |
| Readiness | Staged `none`, `placeholder`, `firstFrame`, `full`, each with `isFinal`. There is no visible failed stage. A failed fetch or decode clears the in-flight record and leaves readiness where it was, so the cell keeps its placeholder, including offline, until it detaches. Retry happens on the next attach, on the host's connectivity-restored signal for still-attached bindings, and through explicit `retry()`. The fetcher reports a failure class (transient or permanent) so the core knows whether connectivity-restored is relevant; neither class is shown as failed. Cancellation is not a failure. The last error is exposed for logging only. The paintable draws the best stage available; painters use the stage only for crossfade, and an instant memory hit has none. |
| Orchestration | The core owns in-flight dedupe by entry identity, cancel when the last binding leaves, priority classes (placeholder, visible, preload) and concurrency caps. |
| Seams | A host `ContentFetcher` (descriptor to bytes or file) owns network, provenance refresh and the disk tier. Decoders are registered per media form (still, vector animation, video, glyph) from adapter packages: fetched data plus spec to paintable with stages. |
| Playback | One shared clock in the core. Per-binding animate gating combines with host-set global pause layers (route moving, fast scroll, low power, panel hidden) under a default policy; the fps cap derives from spec size. The host feeds a connectivity-restored signal; the core never touches the network. Paintables never schedule timers. |
| Budgets | Byte-accounted tiered LRU with host-configurable budgets and defaults. Entries with live bindings are pinned. Unattached ready entries stay until pressure. `clearAll` and a memory-pressure hook exist. Eviction never invalidates a live binding. Releasing by distance is the surface's job, through detach. |
| Scope | One host-created instance provided through a widget scope and by explicit injection. No static singleton. |
| Threading | Decoders may use isolates or native threads. The core is single-threaded on the UI isolate; listener callbacks and painting happen there. |
| Test seam | The package ships in-memory adapters (`FakeFetcher`, `FakeDecoder`, manual clock) and contract suites every adapter must pass. Production code never downcasts. |

## Why

- Telegram's pipeline has five layers with cache identity that includes size and spec, playback gating, byte budgets, and no retained failure. Android and iOS show the placeholder indefinitely when a load fails; offline cells keep it.
- The old cache exposed only readiness, so consumers downcast to the in-memory implementation. Evicting an entry could corrupt a live binding's reference count. Each panel page built its own cache, contradicting ADR 006.
- The system emoji font rasterises each colour glyph on the raster thread the first time it appears, and on every frame on the Skia renderer. Measured on a 120 Hz phone, the first catalogue pass dropped 21 of 455 frames and a paced offscreen warm-up did not remove the cost. Baking pays it once, paced and persisted.
- A sprite is a page handle plus a rectangle, so the same capability can later carry animated media through a dynamic page pool without a second engine.
- Sharing page residency between the atlas and the bindings keeps hold counts and the memory ceiling in one place, and keeps `panel_catalog` ignorant of atlas types: it sees an `AssetPaintable` and its sprite capability.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Decoded `ui.Image` per tick as the only surface | Vector animation becomes bitmaps with no batching across leaves; `ImageProvider` or a widget per item does not fit a custom render object |
| Closed surface-class enum; key-only identity | It cannot express DPR and duplicates identical pixels |
| Three-state readiness; a visible failed stage (sticky or soft with bounded retry) | Telegram never shows one; offline cells keep their placeholder |
| One loader doing fetch and decode | Every codec adapter would reimplement fetching and the disk cache |
| Host-supplied finished paintables | Everyone reimplements dedupe, cancel and priority |
| Per-surface tickers or self-scheduling paintables; no budgets; count-based LRU | Unbounded memory and uncoordinated animation |
| Static singleton; per-surface instances | Hidden global state, or duplicated pixels |
| Unicode as a synchronously final paragraph paintable | First sight of each glyph costs raster time inside the frame |
| Per-binding ownership of glyph pixels | Eviction could corrupt a live binding, and one page could not be drawn in one batch |
| Atlas created and owned by the cache | The glyph list and the pause signals belong to the host and page; the cache would need data-layer knowledge |

## Related

- Panel-side view and acceptance: [ADR 006](006-panel-catalog-viewport.md) (amendment); cache and invalidation QA: [qa-glyph-cache.md](../panel-catalog/qa-glyph-cache.md)
- Glossary: [Content and assets](../content/CONTEXT.md), [Panel Catalog](../panel-catalog/CONTEXT.md) (glyph atlas group)
