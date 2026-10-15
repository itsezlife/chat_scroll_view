# Changelog

All notable changes to `catalog_assets` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- **Disk cache for baked pages.** `GlyphAtlasPersistence` (a `GlyphCacheStore`,
  a `GlyphArtVersionSource` and the density) makes a `GlyphAtlas` persist its
  pages: the next launch restores them one page per frame instead of baking
  (`GlyphCacheVerdict.hit`); an art or catalogue change keeps the old pages
  drawing while the new set bakes behind them and swaps in one step
  (`stale`); a density, glyph size or `GlyphAtlasLayout.version` change
  discards them (`discard`); damaged or missing pages are a miss, baked again.
  `GlyphCacheKey`, `GlyphCacheRecord`, `GlyphCacheStore` (committed and staged
  generations), `MemoryGlyphCacheStore`, `createGlyphCacheStoreForPlatform`
  (a `dart:io` file store, in memory on the web), `FixedGlyphArtVersion`,
  `GlyphAtlas.cacheReport` (verdict and how long circles lasted). Fakes and
  contract suites in `testing.dart`: `FakeGlyphCacheStore`,
  `FakeGlyphArtVersionSource`, `runGlyphCacheStoreContract`.
  `GlyphAtlas`, `createGlyphAtlasForPlatform` take `persistence:` instead of
  `store:` (exactly one); `store:` is now optional.

- **Baked sprites for surfaces.** `GlyphAtlas` (baker, scheduler and resident
  page images behind `spriteOf`), `AtlasSprite`, `MemoryGlyphPageStore`, and
  `createGlyphAtlasForPlatform` (an atlas on baking platforms, `null` on the
  web). `CatalogAssetBinding.sprite` is the optional sprite capability;
  `CatalogAssetCache.glyphAtlas` exposes the atlas to the surface;
  `MemoryCatalogAssetCache(glyphAtlas:)` resolves unicode sprites from it,
  notifies binding listeners when a page lands, and has a `dispose()`.
  Implementers of `CatalogAssetCache` / `CatalogAssetBinding` must add the new
  members (return `null` for no atlas / no sprite).

- **Glyph atlas** (`glyph_atlas.dart`) — `GlyphAtlasLayout` (2048 px pages, glyph
  capped at 72 px, 2 px gutter), `GlyphAtlasIndex` / `GlyphSprite`, the paced
  `GlyphBaker`, and the `GlyphRasteriser` / `GlyphPageStore` seams with
  `ParagraphGlyphRasteriser`. Independent of the asset cache.
- **`testing.dart`** — `FakeGlyphRasteriser`, `FakeGlyphPageStore`,
  `ImagePixels` and the `runGlyphRasteriserContract` /
  `runGlyphPageStoreContract` suites.

- **Paced baking** — `GlyphBakeScheduler` drives the baker one step per frame
  from an injected `BakeFrameSource` and clock; `BakeGovernor` adapts glyphs
  per frame (up to 16) to measured frame cost; `BakePauseSignals` pause it for
  a hidden panel, scrolling and the open animation. `GlyphBaker.prioritise`
  bakes the pages holding the visible glyphs first. Fakes and
  `runBakeFrameSourceContract` ship in `testing.dart`.

- **Page ownership and residency.** `GlyphPageResidency` owns the resident atlas
  pages: a hold count per page, a retention time-to-live (default 60 s, set
  with `retention`) layered on keep-until-pressure, and release of every page
  on memory pressure (`SystemMemoryPressure`). `GlyphAtlas(residency:)`,
  `GlyphAtlas.residency`, `GlyphAtlas.holdPageOf`; the atlas holds all pages
  while its panel is visible. Unicode bindings of `MemoryCatalogAssetCache`
  hold their glyph's page from attach to detach. `createGlyphAtlasForPlatform`
  takes an optional `residency`. `testing.dart` adds `ManualRetentionTimers` and
  `ManualMemoryPressure`.

### Fixed

- `MemoryCatalogAssetCache`: a binding detaching after `evict` / `clear` no
  longer decrements the attach count of a newer entry with the same key (it
  made a live surface look unretained and could drop its loading entry). A
  binding now releases the entry it attached to.

### Changed

- `GlyphAtlas.spriteOf` reads a baked page that was released back from the
  store (a side effect of asking, listeners hear the page when it is drawable
  again), and page listeners are also told when a page is released. A sprite
  is valid only until its page is released; ask again to draw.

- `GlyphBaker` no longer bakes strictly in page order once `prioritise` is
  called; without it the order is unchanged. A page in progress that holds none
  of the prioritised glyphs is dropped and bakes again later.
- The package now depends on the Flutter SDK (`dart:ui` for the baker) and on
  `flutter_test` (contract suites); its tests run with `flutter test`.

### Changed

- **Ready/failed retention** — after the last [CatalogAssetBinding.detach],
  settled entries stay in [MemoryCatalogAssetCache] so re-attach keeps
  readiness (pager keep-alive leave/return). Loading-only orphans are still
  dropped. [CatalogAssetCache.readinessOf] is on the interface;
  [MemoryCatalogAssetCache.evict] / [clear] for explicit drop.

## [0.1.0] - 2026-08-25

### Added

- **`CatalogAssetCache`** — process-wide attach/refcount contract for catalog and
  conversation leaves (key + cache-type / size class + readiness).
- **`CatalogAssetKey`** — sealed unicode / document identity for cache lookup.
- **`CatalogAssetCacheType`** — size-class attach hint (e.g. keyboard vs inline).
- **`CatalogAssetReadiness`** — `loading` / `ready` / `failed` observation.
- **`CatalogAssetBinding`** — surface bind handle with readiness listener.
- **`MemoryCatalogAssetCache`** — in-memory implementation for hosts and tests.
- **`FakeCatalogAssetCache`** — deterministic readiness for widget tests.
- **Unit tests** at the public cache API.

### Non-goals

- No RenderObject dependency; fetch/decode orchestration stays in hosts.
