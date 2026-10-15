# catalog_assets

Process-wide global catalog asset cache for catalog and conversation leaves.

## Contract

- Bind by key + cache-type / size class
- Observe leaf readiness: `loading` / `ready` / `failed` (`readinessOf`)
- Attach / detach: `isRetained` while a surface is bound; ready/failed entries
  survive the last detach (pager leave/return); loading-only orphans drop
- Fetch/decode stays outside this package; `MemoryCatalogAssetCache` /
  `FakeCatalogAssetCache` drive readiness for hosts and deterministic tests
- Explicit `evict` / `clear` for memory pressure (no LRU yet)

No scroll-viewport RenderObject dependency.

## Glyph atlas (`glyph_atlas.dart`, `testing.dart`)

Bakes the glyphs a host supplies into fixed-size **glyph atlas pages** and
answers where each **baked glyph** (sprite: page plus source rectangle) is.
`MemoryCatalogAssetCache(glyphAtlas: …)` exposes it to the surfaces that bind
through the cache: unicode bindings resolve `sprite` from it and every binding
listener hears a page landing. The viewport consumes it. Each unicode binding
**holds the page its glyph is on** from attach to detach; the pages themselves
sit in the atlas's `GlyphPageResidency` (see below), so evicting or clearing a
cache entry never changes a count.
Terms: [Panel Catalog glossary](../../docs/panel-catalog/CONTEXT.md)
(Glyph atlas page, Bake, Baked glyph).

| Piece | Role |
| --- | --- |
| `GlyphAtlasLayout` | Page 2048 px, glyph capped at 72 px, 2 px gutter: 676 cells per page; the three constants are the only knobs |
| `GlyphAtlasIndex` | Fixed plan: which page and cell each glyph is baked into (pure data) |
| `GlyphBaker` | Strips of a few glyphs, then one page composed per step; the caller paces the steps |
| `GlyphRasteriser` (seam) | Paints one glyph; `ParagraphGlyphRasteriser` uses the system font |
| `GlyphPageStore` (seam) | Keeps composed pages; the in-memory fake is in `testing.dart` |
| `GlyphBakeScheduler` | Runs one baker step per frame, only while the pause signals allow; resumes after a few quiet frames |
| `BakeGovernor` / `BakePacing` | Glyphs per frame (up to 16) from measured frame cost: halves near the budget, climbs back while cheap |
| `BakePauseSignals` | Three host-owned `ValueListenable<bool>`: panel visible, scrolling, panel opening |
| `BakeFrameSource` (seam) | The frame clock: `SchedulerBakeFrameSource` in an app, `FakeBakeFrameSource` in tests |
| `GlyphAtlas` | A host's whole bake: baker + scheduler + the page images sprites are drawn from; `spriteOf(glyph)` is null until the glyph's page is baked and loaded |
| `GlyphPageResidency` | Owns the resident page images: a hold count per page (bindings, and the open panel for every page), a retention time-to-live (default 60 s, `retention:`) once nothing holds a page, release of all pages at once on `memoryPressure` |
| `SystemMemoryPressure` | The platform's memory-pressure signal as a `Listenable` (the production `memoryPressure`) |
| `AtlasSprite` | Page image + source rectangle; the optional sprite capability of `CatalogAssetBinding.sprite` |
| `MemoryGlyphPageStore` | In-memory page store (a disk store replaces it later) |
| `createGlyphAtlasForPlatform` | The platform strategy: an atlas on Android, iOS and desktop, `null` on the web (draw text, start no bake) |

Host contract:

| The host provides | The host must not |
| --- | --- |
| The glyph list (the data layer decides which glyphs exist) | Ask the baker to detect missing glyphs or fall back to a paragraph |
| Pacing: a `GlyphBakeScheduler` on a `BakeFrameSource` (or its own calls to `step`) | Call `step` from a spawned isolate (text and picture APIs are root-isolate only) |
| The three pause signals, updated from the real viewport and panel | Bake beside a fling or the open animation; a hidden panel bakes nothing |
| `prioritise(glyphs)` with the visible band when scrolling settles | Expect a visible glyph before its whole page is composed; cells never move |
| `dispose()` on the scheduler (and `SchedulerBakeFrameSource`) when the panel is torn down | Dispose the baker first: the scheduler leaves no frame request or listener behind |
| A `GlyphPageStore` | Mutate or share a stored page; handles are cloned on write and read |
| A `GlyphPageResidency` per atlas: `retention` and `memoryPressure: SystemMemoryPressure()` (the host disposes the signal) | Keep a sprite across frames: a page can be released, ask `spriteOf` again; expect memory back from a released page while the store is the in-memory one (it keeps the texture) |

`testing.dart` ships `ManualRetentionTimers` and `ManualMemoryPressure` (the retention
and the pressure a test moves by hand), `FakeGlyphRasteriser` (predictable pixels, no emoji font;
`onPaint` to model a slow or failing glyph), `FakeGlyphPageStore`,
`FakeBakeFrameSource` and `ManualBakeClock` (frames and time a test steps),
`ImagePixels`, and the contract suites `runGlyphRasteriserContract`,
`runGlyphPageStoreContract` and `runBakeFrameSourceContract` for adapter authors.
On-device checks: `example/integration_test/glyph_atlas_bake_test.dart` (bake
and visual check) and `glyph_atlas_paced_bake_test.dart` (paced bake idle, while
the panel opens, during a fling).
