# catalog_assets

The asset cache core of the catalogue packages: what a surface binds to, how
far an asset has come, how long it is kept, what advances its animation, and
the baked glyph atlas that unicode glyphs are drawn from.

Entry points: `catalog_assets.dart` (the cache core), `glyph_atlas.dart` (the
atlas: planning, baking, paging), `testing.dart` (opt-in fakes and contract
suites). No scroll-viewport RenderObject dependency. Depends on
`content_model` (`ContentKey`, `Observable`) only.

## The cache core

A host creates one `AssetCacheScope` and hands it to the surfaces that draw
content. A surface calls `attach(key, spec, profile)` and gets an
`AssetBinding`; it reads `binding.readiness` and `binding.paintable`,
repaints when the binding signals, and calls `detach()` when it stops showing
the content.

| Type | Role |
| --- | --- |
| `AssetCacheScope` | Host-created instance (no static singleton); owns entries, the default clock and placeholder, and nothing it was handed. `attach`, `clearAll`, `connectivityRestored`, `dispose`; `glyphSource`, `budgets` |
| `AssetSpec` | What is decoded: pixel size at density, decode mode (`original` / `template`), variant (`full` / `firstFrame`). With the `ContentKey` it is the entry identity |
| `AssetProfile` | Per-attach behaviour: animate, loop, autoplay first frame, corner radius. Never splits an entry |
| `AssetBinding` | One surface's live attach: `readiness`, `paintable`, `lastError`, `isPlaying`, `visible`, `paint`, `retry`, `detach`; an `Observable` |
| `AssetPaintable` | What a binding yields: `paint(canvas, rect, context)`, `isAnimated`, and an optional `sprite` (atlas page + source rectangle) for surfaces that batch |
| `AssetStage` / `AssetReadiness` | `none`, `placeholder`, `firstFrame`, `full` and `isFinal`. There is no failed stage |
| `AssetProducer` (seam) | Makes the paintables of entries: `produce(request, progress)` returns an `AssetTask`; reports stages, failures and cancellation through `AssetProgress` |
| `AssetCacheBudgets` | Byte budgets of the unattached entries per tier (`still`, `animated`); documented defaults |
| `PlaybackClock` / `PlaybackPolicy` | One shared animation clock, per-binding gating, host-set pause layers (`PlaybackPauseLayer`), fps caps derived from the spec size |
| `PlaybackTickSource` (seam) | The clock's per-frame callback; `SchedulerPlaybackTickSource` in an app, `ManualPlaybackTickSource` in tests |
| `GlyphSpriteSource` (seam) | The one narrow seam to baked glyphs: `spriteOf`, `holdPageOf`, page listeners. `GlyphAtlas` implements it |
| `AtlasSprite` | Page image + source rectangle; the sprite capability of an `AssetPaintable` |

Behaviour that matters to a surface:

- **Staged readiness, no visible failure.** A binding paints the best stage
  its entry has reached, the scope's placeholder before any. An attempt that
  fails (offline, server error, bad data) leaves the stage where it was, so a
  cell keeps its placeholder until detached. Nothing is signalled; the error
  is `lastError`, for logs. The attempt is repeated on the next attach, on
  `connectivityRestored()` (for failures the producer called transient, and
  only for entries still attached) and on `retry()`. Cancellation is not a
  failure.
- **Pinning and the budget.** An entry with a live binding is never evicted.
  Unattached entries that reached a first frame or better stay until the byte
  budget of their tier needs the room (least recently used first), or until
  `clearAll()` / the memory-pressure signal; one that produced nothing beyond
  a placeholder is dropped at the last detach, and a running attempt is
  cancelled then. Eviction can never invalidate a binding: a binding gives
  back exactly what it took, once, and never looks its entry up again.
- **One attempt per entry**, however many surfaces attach.
- **Playback.** A binding is advanced by the shared clock when its profile
  animates, it is `visible`, its paintable `isAnimated` and no pause layer is
  set. The clock asks the engine for frames only while something plays.
  Paintables never schedule timers; they derive their frame from the context
  time.
- **Threading.** Single-threaded on the UI isolate: calls, producer reports,
  listeners and painting. Decoding may happen elsewhere; its results are
  reported here from the UI isolate.

### The glyph media form

A unicode key bound in a scope that has a glyph source registered
(`scope.glyphSource = atlas`) is the glyph form: a baked sprite on an atlas
page, never a paragraph at scroll time on a platform that bakes. It is
placeholder-stage (a circle) with no time limit until its glyph is baked, then
final at `full` with a sprite. The binding **holds the page its glyph is on**
from attach to detach (a count, never pixels) and has no cache entry, so the
budget cannot evict it and nothing the cache does can change a hold. The pages
belong to the source (the atlas's `GlyphPageResidency`): shared by the
bindings that hold them and by the atlas itself, kept for the retention after
the last hold and released under memory pressure unless held. Registering a new
source moves live bindings to it in place. Without a registered source a
unicode key is an ordinary entry, which is how a platform that draws glyphs as
text plugs a producer that does.

### Defaults and how they were chosen

Measured by `test/benchmark/asset_cache_churn_bench_test.dart` (run
`flutter test test/benchmark`): a scroll trace down a catalogue and back, one
row at a time, counting how many attaches on the way back find their entry
still decoded. Cell sizes are decoded RGBA at 3x density; an animated entry
costs two frame buffers, as the Android client counts a Lottie drawable.

| Workload | 4 MiB | 8 MiB | 12 MiB | 16 MiB | 24 MiB | 32 MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stickers, 192 px (144 KiB), 24 visible, down 4 screens and back | 4% | 33% | 63% | 92% | 100% | 100% |
| Stickers, down 8 screens and back | 2% | 17% | 31% | 46% | 75% | 100% |
| Custom emoji, 102 px (40 KiB), 64 visible, down 4 screens and back | 13% | 53% | 91% | 100% | 100% | 100% |
| Custom emoji, down 8 screens and back | 6% | 27% | 45% | 66% | 100% | 100% |
| Animated stickers, 256 px (512 KiB), 12 visible, down 1 screen and back | 0% | 25% | 100% | 100% | 100% | 100% |
| Animated stickers, down 2 screens and back | 0% | 13% | 50% | 75% | 100% | 100% |
| Animated stickers, down 4 screens and back | 0% | 6% | 25% | 38% | 75% | 100% |

- **`AssetCacheBudgets.defaults`: 24 MiB of stills, 12 MiB of animations.**
  24 MiB keeps all of the last four screens of stickers and of custom emoji
  (pager keep-alive and scroll-back); 12 MiB of animations keeps the one screen
  just scrolled past. Both are within the Android client's own figures (a 15
  to 30 MB bitmap cache, a 10 MiB animation cache). Pinned bytes come out of
  the budget first.
- **`PlaybackPolicy` fps caps: 30 fps up to 270 px on the longer edge (90 dp at
  density 3, Android's rule for emoji; Desktop repaints no faster than every
  33 ms), 60 fps above.** A cap is a ceiling, not a target: on a 120 Hz display
  an uncapped animation would repaint its surface twice as often for no visible
  gain. The benchmark's playback line shows the cap halving repaint requests
  for small assets (30000 against 60000 over 600 frames and 100 bindings) at
  about 25 us of dispatch per frame in debug mode.
- Churn cost: about 2.5 us (debug mode) per attach, produce, detach and
  eviction cycle on a 5000-entry catalogue through a 24 MiB budget. Absolute
  times are inflated by asserts and are never asserted; the hit-rate tables are
  counts and are exact.

### Host contract

| The host provides | The host must not |
| --- | --- |
| One `AssetCacheScope` per cache it wants shared, created once and disposed when it goes away | Keep a static instance, or create one per surface (entries would not be shared) |
| A `producer` that makes the paintables of non-glyph content, reporting through `AssetProgress` on the UI isolate | Report from another isolate or thread, or throw for a failed attempt (report `fail`) |
| A `glyphSource` (the atlas) on platforms that bake glyphs; no source where glyphs are drawn as text | Pass a `GlyphAtlas` to anything but `glyphSource`, or read atlas types through the cache |
| Budgets for its device class (`budgets`) and the memory-pressure signal (`memoryPressure:` or `clearAll()`) | Evict by hand to "free" a bound entry: bound entries are pinned |
| `connectivityRestored()` when the network returns | Make the cache touch the network |
| Pause layers on the clock (`routeMoving`, `fastScroll`, `lowPower`, `surfaceHidden`) | Run a timer per animation, or call a paintable's `paint` outside a paint |
| `detach()` for every binding it attached, `visible` set to what it shows | Keep a `paintable` or a `sprite` across frames: a better stage replaces one, a page release can end the other |

Decisions: [ADR 006](../../docs/adr/006-panel-catalog-viewport.md) (the
amendment on baked glyphs and the shared asset scope). The asset cache ADR
(cache core, staged readiness, producer seam) is promoted with the
package-architecture documents.

## Glyph atlas (`glyph_atlas.dart`, `testing.dart`)

Bakes the glyphs a host supplies into fixed-size **glyph atlas pages** and
answers where each **baked glyph** (sprite: page plus source rectangle) is.
`AssetCacheScope.glyphSource = atlas` exposes it to the surfaces that bind
through the scope: unicode bindings resolve their `paintable.sprite` from it
and every binding hears a page landing. The viewport consumes it. Each unicode
binding **holds the page its glyph is on** from attach to detach; the pages
themselves sit in the atlas's `GlyphPageResidency` (see below), so nothing done
to the cache ever changes a count. The atlas implements `GlyphSpriteSource`,
the only thing the cache knows about it.
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
| `GlyphAtlas` | A host's whole bake: baker + scheduler + the page images sprites are drawn from; `spriteOf(glyph)` is null until the glyph's page is baked and loaded; `retire()` hands the drawn art to the atlas that replaces it (`predecessor:`) |
| `GlyphPageResidency` | Owns the resident page images: a hold count per page (bindings, and the open panel for every page), a retention time-to-live (default 60 s, `retention:`) once nothing holds a page, release of the pages nothing holds, at once, on `memoryPressure` (a held page, such as any page while the panel is open, is kept) |
| `SystemMemoryPressure` | The platform's memory-pressure signal as a `Listenable` (the production `memoryPressure`) |
| `MemoryGlyphPageStore` | In-memory page store, for an atlas that does not persist |
| `GlyphAtlasPersistence` | `GlyphCacheStore` + `GlyphArtVersionSource` + density: an atlas given this instead of a store restores its pages on the next launch |
| `GlyphCacheStore` (seam) | One committed generation (what the next launch finds) and at most one staged one; `createGlyphCacheStoreForPlatform(path)` is a `dart:io` file store, in memory on the web; `FakeGlyphCacheStore` in `testing.dart` |
| `GlyphCacheKey` | Art version + density + glyph size + layout version + catalogue hash; decides hit, stale, discard or miss |
| `GlyphArtVersionSource` (seam) | Says whether the system emoji art changed; `FixedGlyphArtVersion`, `ComputedGlyphArtVersion` (a pixel fingerprint computed once; `GlyphPixelReader` draws the sentinels); `FakeGlyphArtVersionSource` in `testing.dart` |
| `GlyphBakeObserver` (seam) | Shown each glyph's baked cell (RGBA bytes) so a glyph-support probe shares the bake pass; `FakeGlyphBakeObserver` in `testing.dart` |
| `createGlyphAtlasForPlatform` | The platform strategy, taking a `GlyphAtlasRequest` (the arguments of `GlyphAtlas` in one value): an atlas on Android, iOS and desktop, `null` on the web (draw text, start no bake) |

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

`testing.dart` is opt-in: production entry points never export or import it.
The contract suites are written with `flutter_test`, so the package lists
`flutter_test` under `dependencies` (a library cannot import a dev dependency).
The suites have no consumer outside this package yet; moving them to a package
of their own would give `catalog_assets` a dev dependency on a package that
depends on it, which the workspace dependency lint rejects as a cycle.

`testing.dart` ships `ManualRetentionTimers` and `ManualMemoryPressure` (the retention
and the pressure a test moves by hand), `FakeGlyphRasteriser` (predictable pixels, no emoji font;
`onPaint` to model a slow or failing glyph), `FakeGlyphPageStore`,
`FakeBakeFrameSource` and `ManualBakeClock` (frames and time a test steps),
`ImagePixels`, `sampleGlyphCatalogue` (a catalogue of the current size without any emoji
data), and the contract suites `runGlyphRasteriserContract`,
`runGlyphPageStoreContract` and `runBakeFrameSourceContract` for adapter authors.
For the cache core: `FakeAssetProducer` (every attempt waits for the test, which
plays the producer through `FakeAssetAttempt`), `FakeAssetPaintable`,
`FakeGlyphSpriteSource` (pages baked and released by hand, hold counts
readable), `ManualPlaybackTickSource`, and the contract suites
`runGlyphSpriteSourceContract` (the fake and `GlyphAtlas` both pass it) and
`runPlaybackTickSourceContract` (the manual and the scheduler source both pass
it).
On-device checks: `example/integration_test/glyph_atlas_bake_test.dart` (bake
and visual check) and `glyph_atlas_paced_bake_test.dart` (paced bake idle, while
the panel opens, during a fling).

## Temporary shim

`legacy_shim.dart` keeps the readiness-flag API (`CatalogAssetCache`,
`MemoryCatalogAssetCache`, `CatalogAssetBinding`, ...) that `panel_catalog` and
`chat_chrome` still call, so the tree stays green while they migrate. Its
baked-glyph half runs on the real glyph form (an internal `AssetCacheScope`
with the atlas registered); only the driven `loading` / `ready` / `failed`
flags are legacy. It is deleted with the migration of those two packages. New
code must not import it.
