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
Independent of the cache above; the cache and the viewport consume it later.
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

Host contract:

| The host provides | The host must not |
| --- | --- |
| The glyph list (the data layer decides which glyphs exist) | Ask the baker to detect missing glyphs or fall back to a paragraph |
| Pacing: a `GlyphBakeScheduler` on a `BakeFrameSource` (or its own calls to `step`) | Call `step` from a spawned isolate (text and picture APIs are root-isolate only) |
| The three pause signals, updated from the real viewport and panel | Bake beside a fling or the open animation; a hidden panel bakes nothing |
| `prioritise(glyphs)` with the visible band when scrolling settles | Expect a visible glyph before its whole page is composed; cells never move |
| `dispose()` on the scheduler (and `SchedulerBakeFrameSource`) when the panel is torn down | Dispose the baker first: the scheduler leaves no frame request or listener behind |
| A `GlyphPageStore` | Mutate or share a stored page; handles are cloned on write and read |

`testing.dart` ships `FakeGlyphRasteriser` (predictable pixels, no emoji font;
`onPaint` to model a slow or failing glyph), `FakeGlyphPageStore`,
`FakeBakeFrameSource` and `ManualBakeClock` (frames and time a test steps),
`ImagePixels`, and the contract suites `runGlyphRasteriserContract`,
`runGlyphPageStoreContract` and `runBakeFrameSourceContract` for adapter authors.
On-device checks: `example/integration_test/glyph_atlas_bake_test.dart` (bake
and visual check) and `glyph_atlas_paced_bake_test.dart` (paced bake idle, while
the panel opens, during a fling).
