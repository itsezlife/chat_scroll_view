# glyph_atlas

The baked glyph atlas of colour emoji: it bakes the glyphs a host supplies
into fixed-size **glyph atlas pages** and answers where each **baked glyph**
is, as an `AtlasSprite` of `mpx_core` (page plus source rectangle).

Surfaces reach an atlas only through `GlyphSpriteSource`, which `GlyphAtlas`
implements and `LayeredGlyphSource` stacks; `content_assets` binds unicode
content to it. Each glyph binding holds the page its glyph is on from attach
to detach; the pages sit in the atlas's `GlyphPageResidency`. Terms:
[Panel Catalog glossary](../../docs/panel-catalog/CONTEXT.md) (Glyph atlas
page, Bake, Baked glyph).

## Pieces

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
| `GlyphAtlas` | A host's whole bake: baker + scheduler + the page images sprites are drawn from; `spriteOf(glyph)` is null until the glyph's page is baked and loaded; `retire()` hands the drawn art to the atlas that replaces it (`predecessor:`) |
| `GlyphPageResidency` | Owns the resident page images: a hold count per page (bindings, and the open panel for every page), a retention time-to-live (default 60 s, `retention:`) once nothing holds a page, release of the pages nothing holds, at once, on `memoryPressure` (a held page, such as any page while the panel is open, is kept) |
| `SystemMemoryPressure` | The platform's memory-pressure signal as a `Listenable` (the production `memoryPressure`) |
| `MemoryGlyphPageStore` | In-memory page store, for an atlas that does not persist |
| `GlyphAtlasPersistence` | `GlyphCacheStore` + `GlyphArtVersionSource` + density: an atlas given this instead of a store restores its pages on the next launch |
| `GlyphCacheStore` (seam) | One committed generation (what the next launch finds) and at most one staged one; `GlyphCacheStore.forPlatform(path)` is a `dart:io` file store, in memory on the web; `FakeGlyphCacheStore` in `testing.dart` |
| `GlyphCacheKey` | Art version + density + glyph size + layout version + catalogue hash; decides hit, stale, discard or miss |
| `GlyphArtVersionSource` (seam) | Says whether the system emoji art changed; `FixedGlyphArtVersion`, `ComputedGlyphArtVersion` (a pixel fingerprint computed once; `GlyphPixelReader` draws the sentinels); `FakeGlyphArtVersionSource` in `testing.dart` |
| `GlyphBakeObserver` (seam) | Shown each glyph's baked cell (RGBA bytes) so a glyph-support probe shares the bake pass; `CallbackGlyphBakeObserver` builds one from three functions (the bridge to a consumer that must not depend on this package); `FakeGlyphBakeObserver` in `testing.dart` |
| `GlyphAtlas.forPlatform` | The platform strategy, taking a `GlyphAtlasRequest` (the arguments of `GlyphAtlas` in one value): an atlas on Android, iOS and desktop, `null` on the web (draw text, start no bake) |

### Disk cache

With a `GlyphAtlasPersistence` the pages outlive the process. A launch reads
the art version, builds the key and compares it with the persisted set:
*hit* restores the pages (one read per frame, waiting only for scrolls and the
open animation), *stale* keeps drawing the old pages while the new set bakes
behind them and swaps once, *discard* and *miss* show circles and bake as on a
first run, persisting each page as it lands. Damaged or missing pages are a
miss for that page. A failing disk is reported once and never stops the bake.
Pages are raw RGBA (16 MiB each, 48 MiB for the current catalogue) with a
length-checked header; the cache directory is the host's (no plugin here) and
may be cleared by the platform at any time. QA steps for the first run, the
cold start and the OS-update case:
[qa-glyph-cache.md](../../docs/panel-catalog/qa-glyph-cache.md).

Host contract:

| The host provides | The host must not |
| --- | --- |
| The glyph list (the data layer decides which glyphs exist) | Ask the baker to detect missing glyphs or fall back to a paragraph |
| Pacing: a `GlyphBakeScheduler` on a `BakeFrameSource` (or its own calls to `step`) | Call `step` from a spawned isolate (text and picture APIs are root-isolate only) |
| The three pause signals, updated from the real viewport and panel | Bake beside a fling or the open animation; a hidden panel bakes nothing |
| `prioritise(glyphs)` with the visible band when scrolling settles | Expect a visible glyph before its whole page is composed; cells never move |
| `dispose()` on the scheduler (and `SchedulerBakeFrameSource`) when the panel is torn down | Dispose the baker first: the scheduler leaves no frame request or listener behind |
| `retire()` on the old atlas, and its `RetiredGlyphArt` given to the new one, when the plan must change | Run two atlases over one `GlyphCacheStore` at once: a cache has a single writer, and the successor waits for the retired atlas's disk work |
| `reportScrolling(reporter:, scrolling:)` from each surface that scrolls | Share one reporter between surfaces, or leave a reporter at `true` when its surface goes away |
| A `GlyphPageStore` | Mutate or share a stored page; handles are cloned on write and read |
| A `GlyphPageResidency` per atlas: `retention` and `memoryPressure: SystemMemoryPressure()` (the host disposes the signal) | Keep a sprite across frames: a page can be released, ask `spriteOf` again; expect memory back from a released page while the store is the in-memory one (it keeps the texture) |

## Disk cache

With a `GlyphAtlasPersistence` the pages outlive the process. A launch reads
the art version, builds the key and compares it with the persisted set: *hit*
restores the pages, *stale* keeps drawing the old pages while the new set
bakes and swaps once, *discard* and *miss* bake as on a first run, persisting
each page as it lands. A failing disk is reported once and never stops the
bake. QA steps: [qa-glyph-cache.md](../../docs/panel-catalog/qa-glyph-cache.md).

## Testing

`testing.dart` (opt-in) ships the fakes (`FakeGlyphRasteriser`,
`FakeGlyphPageStore`, `FakeGlyphCacheStore`, `FakeGlyphArtVersionSource`,
`FakeGlyphBakeObserver`, `FakeBakeFrameSource`, `FakeGlyphSpriteSource`), the
manual clocks and signals (`ManualBakeClock`, `ManualRetentionTimers`,
`ManualMemoryPressure`), `ImagePixels`, `SampleGlyphCatalogue`, and the
contract suites for `GlyphRasteriser`, `GlyphPageStore`, `GlyphCacheStore`,
`BakeFrameSource` and `GlyphSpriteSource`.
